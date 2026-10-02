//! Execution asynchrone des operations du backend.
//!
//! C'est LE correctif de fond de la 0.2. Jusqu'ici, chaque installation, chaque
//! recherche et chaque mise a jour s'executait sur le fil de l'interface: la
//! fenetre restait figee, sans curseur d'attente, parfois plusieurs minutes.
//! L'utilisateur ne pouvait pas distinguer une longue installation d'un
//! plantage.
//!
//! Les fonctions du backend restent volontairement bloquantes (elles appellent
//! `flatpak`, `auxi`, `apt-cache`): les envelopper ici dans `spawn_blocking`
//! evite de teinter tout le backend d'`async`, et garde le mode `--cli`
//! utilisable sans runtime.
//!
//! TOUT le contact avec l'API de tache de libcosmic est concentre dans
//! `background()`. Si cette API bouge d'une version a l'autre, une seule
//! fonction est a corriger, pas les six pages de l'interface.

use cosmic::app::Task;

use crate::ui::Message;

/// Lance `work` sur un fil de travail et renvoie son resultat sous forme de
/// message. L'interface reste reactive pendant toute la duree de l'operation.
pub fn background<T, F, M>(work: F, to_message: M) -> Task<Message>
where
    F: FnOnce() -> T + Send + 'static,
    T: Send + 'static,
    M: FnOnce(T) -> Message + Send + 'static,
{
    // `cosmic::task::future` accepte un futur dont la sortie se convertit en
    // `cosmic::Action<Message>`; `impl<M> From<M> for Action<M>` fait le reste.
    cosmic::task::future(async move {
        match tokio::task::spawn_blocking(work).await {
            Ok(value) => to_message(value),
            // La tache a panique. On ne propage pas la panique dans la boucle
            // d'evenements: l'interface doit survivre a l'echec d'une seule
            // operation.
            Err(_) => Message::TaskPanicked,
        }
    })
}

/// Lance une operation longue dont chaque ligne de sortie remonte a
/// l'interface PENDANT qu'elle s'execute (`Message::OpLine`), puis son resultat
/// (`Message::OpFinished`).
///
/// `work` recoit la fonction a appeler pour chaque ligne. Il tourne sur un fil
/// de travail, comme dans `background()`; les lignes traversent un canal non
/// borne pour que le fil ne soit jamais bloque par l'affichage.
pub fn streamed<F>(work: F) -> Task<Message>
where
    F: FnOnce(&mut dyn FnMut(&str)) -> crate::model::ActionResult + Send + 'static,
{
    use cosmic::iced::futures::channel::mpsc;
    use cosmic::iced::futures::stream::{self, StreamExt};

    // Le fil n'est cree qu'au premier sondage du flux, donc dans le runtime
    // tokio de l'application: `spawn_blocking` panique en dehors.
    let messages = stream::once(async move {
        let (tx, rx) = mpsc::unbounded::<Message>();
        tokio::task::spawn_blocking(move || {
            let mut forward = |line: &str| {
                let _ = tx.unbounded_send(Message::OpLine(line.to_string()));
            };
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                work(&mut forward)
            }));
            // Meme regle que `background()`: une panique ne doit pas emporter
            // l'interface, ni la laisser croire que l'operation tourne encore.
            let result = result.unwrap_or_else(|_| {
                crate::model::ActionResult::err(
                    "L'operation s'est interrompue de facon inattendue. Le detail \
                     ci-dessous montre ce qu'elle a eu le temps d'ecrire.",
                )
            });
            let _ = tx.unbounded_send(Message::OpFinished(result));
        });
        rx
    })
    .flatten();

    cosmic::task::stream(messages)
}
