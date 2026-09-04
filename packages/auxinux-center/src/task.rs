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
