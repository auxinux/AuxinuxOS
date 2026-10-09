// AuxiNuxOS: retire KDE Discover des lanceurs de la barre des taches.
//
// Le gestionnaire de taches de Plasma epingle Discover PAR DEFAUT (main.xml de
// org.kde.plasma.taskmanager: systemsettings, discover, gestionnaire de
// fichiers, navigateur). Or Discover n'est pas installe -- il est ecarte a
// dessein, voir check-rootfs.sh -- et c'est le centre de controle qui joue ce
// role. Resultat constate: une icone blanche « org.kde.discover.desktop » dans
// la barre, qui ne lance rien.
//
// Pourquoi un script de mise a jour et pas /etc/xdg/plasma-*-appletsrc: c'est
// la voie qu'emprunte le fond d'ecran (configure-branding.sh), et il n'est PAS
// applique -- constate en VM le 2026-10-02, le bureau garde le fond de Plasma.
// Les scripts de ce dossier, eux, s'executent UNE fois par utilisateur, APRES
// la creation de la disposition par defaut (shellcorona.cpp,
// processUpdateScripts), et aussi pour les comptes qui existent deja. Verifie
// en VM le meme jour: Discover disparait de la barre au redemarrage de
// plasmashell, les autres lanceurs restent.
//
// On ne retire QUE Discover: un utilisateur qui a epingle ses propres
// applications les garde.

var TYPES = ["org.kde.plasma.icontasks", "org.kde.plasma.taskmanager"];
// Valeur par defaut de Plasma 6.3, lue quand la cle n'a jamais ete ecrite.
var DEFAUT = [
    "applications:systemsettings.desktop",
    "applications:org.kde.discover.desktop",
    "preferred://filemanager",
    "preferred://browser"
];

var tous = panels();
for (var p = 0; p < tous.length; ++p) {
    for (var t = 0; t < TYPES.length; ++t) {
        var taches = tous[p].widgets(TYPES[t]);
        for (var w = 0; w < taches.length; ++w) {
            var tache = taches[w];
            tache.currentConfigGroup = ["General"];
            var lanceurs = tache.readConfig("launchers", DEFAUT);
            if (typeof lanceurs === "string") {
                lanceurs = lanceurs.split(",");
            }
            var gardes = [];
            for (var i = 0; i < lanceurs.length; ++i) {
                if (String(lanceurs[i]).indexOf("org.kde.discover") === -1) {
                    gardes.push(lanceurs[i]);
                }
            }
            if (gardes.length !== lanceurs.length) {
                tache.writeConfig("launchers", gardes);
                tache.reloadConfig();
            }
        }
    }
}
