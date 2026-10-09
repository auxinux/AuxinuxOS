// AuxiNuxOS: fond d'ecran par defaut du bureau.
//
// configure-branding.sh l'ecrivait dans /etc/xdg/plasma-org.kde.plasma.desktop-
// appletsrc, sous le numero de la vue bureau. Constate en VM le 2026-10-02: ce
// fond n'etait PAS applique, le bureau gardait celui de Plasma (« Next »).
// Comme auxinux-sans-discover.js, ce script s'execute une fois par
// utilisateur, juste apres la creation de sa disposition par defaut.
//
// On ne remplace QUE le fond par defaut. Un utilisateur qui a choisi le sien le
// garde, y compris si ce script arrive sur un compte qui existe deja.

var IMAGE = "file:///usr/share/backgrounds/auxinuxos/default.png";

var bureaux = desktops();
for (var i = 0; i < bureaux.length; ++i) {
    var bureau = bureaux[i];
    if (bureau.wallpaperPlugin !== "org.kde.image") {
        continue;
    }
    bureau.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    var actuelle = String(bureau.readConfig("Image", ""));
    // Vide: Plasma affiche son fond par defaut. Notre propre chemin peut deja
    // y figurer (lu depuis /etc/xdg) sans etre affiche: on le reecrit.
    if (actuelle === "" ||
        actuelle.indexOf("/wallpapers/Next") !== -1 ||
        actuelle.indexOf("/usr/share/backgrounds/auxinuxos/") !== -1) {
        bureau.writeConfig("Image", IMAGE);
    }
}
