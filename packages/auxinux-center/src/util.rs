//! Helpers d'execution de commandes externes.
//!
//! Le Center delegue tout le travail aux outils systeme deja presents:
//! `flatpak`, la CLI `auxi` (politique APT maison) et `apt-cache`. Les
//! operations privilegiees passent par `pkexec`, TOUJOURS sur un programme
//! installe a un emplacement fixe appartenant a root -- jamais sur un script
//! genere a la volee dans un repertoire temporaire.

use std::io::Read;
use std::process::{Command, Stdio};
use std::sync::mpsc;

pub struct Output {
    pub ok: bool,
    /// Code de sortie; `None` si le programme n'a pas pu etre lance ou a ete
    /// tue par un signal.
    pub code: Option<i32>,
    pub stdout: String,
    pub stderr: String,
}

/// Execute une commande et capture sa sortie.
pub fn run(cmd: &str, args: &[&str]) -> Output {
    match Command::new(cmd).args(args).output() {
        Ok(o) => Output {
            ok: o.status.success(),
            code: o.status.code(),
            stdout: String::from_utf8_lossy(&o.stdout).to_string(),
            stderr: String::from_utf8_lossy(&o.stderr).to_string(),
        },
        Err(e) => Output {
            ok: false,
            code: None,
            stdout: String::new(),
            stderr: format!("{cmd}: {e}"),
        },
    }
}

/// Execute une commande privilegiee via pkexec (declenche l'agent polkit).
/// `args[0]` est le programme a lancer en root, le reste ses arguments.
pub fn run_pkexec(args: &[&str]) -> Output {
    run("pkexec", args)
}

/// Execute une commande en transmettant chaque ligne a `on_line` DES QU'ELLE
/// EST ECRITE, sortie standard et erreur melangees dans l'ordre d'arrivee.
///
/// `run()` n'attendait que la fin: une mise a jour de dix minutes restait muette
/// pendant dix minutes, puis ne rendait que la sortie d'erreur -- vide quand apt
/// s'arretait sur une question, qu'il pose sur la sortie standard.
///
/// Les retours chariot comptent comme des fins de ligne: c'est ainsi que
/// flatpak et wget redessinent leur ligne d'avancement.
pub fn run_streaming(cmd: &str, args: &[&str], on_line: &mut dyn FnMut(&str)) -> Output {
    let spawned = Command::new(cmd)
        .args(args)
        // Personne ne peut repondre a une question: une entree fermee la fait
        // echouer tout de suite au lieu de bloquer l'operation indefiniment.
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn();
    let mut child = match spawned {
        Ok(child) => child,
        Err(e) => {
            let message = format!("{cmd}: {e}");
            on_line(&message);
            return Output {
                ok: false,
                code: None,
                stdout: String::new(),
                stderr: message,
            };
        }
    };

    let (tx, rx) = mpsc::channel::<(bool, String)>();
    let mut readers = Vec::new();
    if let Some(out) = child.stdout.take() {
        readers.push(forward_lines(out, false, tx.clone()));
    }
    if let Some(err) = child.stderr.take() {
        readers.push(forward_lines(err, true, tx.clone()));
    }
    // Sans ce drop, le canal ne se fermerait jamais et la boucle attendrait
    // indefiniment apres la fin du programme.
    drop(tx);

    let mut stdout = String::new();
    let mut stderr = String::new();
    for (is_err, line) in rx {
        on_line(&line);
        let target = if is_err { &mut stderr } else { &mut stdout };
        target.push_str(&line);
        target.push('\n');
    }
    for reader in readers {
        let _ = reader.join();
    }

    match child.wait() {
        Ok(status) => Output {
            ok: status.success(),
            code: status.code(),
            stdout,
            stderr,
        },
        Err(e) => Output {
            ok: false,
            code: None,
            stdout,
            stderr: format!("{stderr}{cmd}: {e}\n"),
        },
    }
}

/// Lit `source` jusqu'a sa fermeture et envoie chaque ligne non vide.
fn forward_lines<R: Read + Send + 'static>(
    mut source: R,
    is_err: bool,
    tx: mpsc::Sender<(bool, String)>,
) -> std::thread::JoinHandle<()> {
    std::thread::spawn(move || {
        let mut pending: Vec<u8> = Vec::new();
        let mut buf = [0u8; 4096];
        loop {
            let n = match source.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => n,
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            };
            for &byte in &buf[..n] {
                if byte == b'\n' || byte == b'\r' {
                    if !pending.is_empty() {
                        let line = String::from_utf8_lossy(&pending).into_owned();
                        pending.clear();
                        if tx.send((is_err, line)).is_err() {
                            return;
                        }
                    }
                } else {
                    pending.push(byte);
                }
            }
        }
        if !pending.is_empty() {
            let _ = tx.send((is_err, String::from_utf8_lossy(&pending).into_owned()));
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn streaming_delivers_both_streams_and_exit_code() {
        let mut seen = Vec::new();
        let out = run_streaming(
            "sh",
            &["-c", "echo un; echo deux >&2; printf 'trois\\rquatre'; exit 3"],
            &mut |l| seen.push(l.to_string()),
        );
        assert!(!out.ok);
        assert_eq!(out.code, Some(3));
        seen.sort();
        assert_eq!(seen, vec!["deux", "quatre", "trois", "un"]);
        assert!(out.stderr.contains("deux"));
        assert!(out.stdout.contains("un"));
    }

    #[test]
    fn streaming_reports_a_missing_program() {
        let mut seen = Vec::new();
        let out = run_streaming("auxinux-programme-absent", &[], &mut |l| seen.push(l.to_string()));
        assert!(!out.ok);
        assert_eq!(out.code, None);
        assert_eq!(seen.len(), 1);
    }

    #[test]
    fn streaming_does_not_wait_for_input() {
        // `read` sur une entree fermee rend immediatement: le test se
        // bloquerait si l'entree standard etait heritee d'un terminal.
        let out = run_streaming("sh", &["-c", "read x; echo fin"], &mut |_| {});
        assert!(out.stdout.contains("fin"));
    }
}
