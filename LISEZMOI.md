# App iPhone orgAnniversaire : publier sans Mac

Ce dossier contient le code de l'app iPhone (SwiftUI + vue web du site). **Il ne va pas sur le serveur o2switch.**
La compilation se fait dans le cloud avec **Codemagic** (offre gratuite : 500 min/mois, une compilation prend environ 10 min).

Ce que fait l'app en plus du site :
- connexion mémorisée ;
- notifications quand un invité répond ;
- import des invités depuis les contacts de l'iPhone ;
- partage natif, retour haptique, mode hors ligne ;
- suppression du compte (exigence Apple 5.1.1).

Les paiements par carte sont masqués dans l'app. L'achat intégré Apple arrivera en phase 2.

---

## Étape 0 : mettre en ligne la partie serveur
Envoyez d'abord `_DEPLOY/APP_IOS_SERVEUR_2026-11-26/a_envoyer/` (voir son LISEZMOI).

## Étape 1 : identifiant de l'app (developer.apple.com)
1. Ouvrez **Certificates, Identifiers & Profiles**, puis **Identifiers**, puis **+**, puis **App IDs**, puis **App**.
2. Remplissez :
   - Description : `orgAnniversaire`
   - Bundle ID (Explicit) : `fr.organniversaire.app`
3. Dans **Capabilities**, cochez **Push Notifications**. Validez.

## Étape 2 : clé de notifications (APNs)
1. Ouvrez **Keys**, puis **+**. Nom : `orgAnniversaire push`. Cochez **Apple Push Notifications service (APNs)**. Validez.
2. **Téléchargez le fichier `.p8`.** Apple ne le propose qu'une seule fois.
3. Notez :
   - le **Key ID** (10 caractères) ;
   - votre **Team ID**, visible en haut à droite du compte développeur.
4. Sur le site, ouvrez **Admin › Configuration › Application iPhone**. Envoyez le `.p8` et saisissez le Key ID, le Team ID et le Bundle ID `fr.organniversaire.app`. Enregistrez.

## Étape 3 : fiche de l'app (appstoreconnect.apple.com)
1. Ouvrez **Apps**, puis **+**, puis **Nouvelle app**. Remplissez :
   - Plateforme : iOS
   - Nom : `orgAnniversaire`
   - Langue : Français
   - Bundle ID : `fr.organniversaire.app`
   - SKU : `organniversaire-ios`
2. Allez dans **Informations sur l'app**. Copiez l'**Identifiant Apple** (une suite de chiffres) et remplacez `0000000000` par ce numéro dans `codemagic.yaml`.

## Étape 4 : clé API App Store Connect (pour Codemagic)
1. Dans App Store Connect, ouvrez **Utilisateurs et accès**, puis **Intégrations**, puis **Clés API de l'App Store Connect**, puis **+**.
2. Nom : `Codemagic`. Accès : **Gestionnaire d'apps** (App Manager).
3. Téléchargez le fichier `.p8` (là aussi, une seule fois).
4. Notez l'**Issuer ID** et le **Key ID**.

## Étape 5 : dépôt GitHub
1. Sur github.com, créez un dépôt **privé** `organniversaire-ios`.
2. Cliquez sur **uploading an existing file** et glissez **le contenu** du dossier `APP_IOS`. À la racine du dépôt, on doit voir `project.yml`, `codemagic.yaml` et le dossier `OrgAnniversaire/`.
3. Validez (Commit) sur la branche `main`.

## Étape 6 : Codemagic
1. Créez un compte sur codemagic.io en vous connectant avec GitHub, puis ajoutez le dépôt `organniversaire-ios`.
2. Ouvrez **Teams › Integrations › Developer Portal**, puis **Connect**, et saisissez :
   - Nom : **`orgAnniversaire ASC`** (exactement ce nom : il est repris dans `codemagic.yaml`) ;
   - l'Issuer ID et le Key ID de l'étape 4 ;
   - le fichier `.p8` de l'étape 4.
3. Allez dans **Code signing identities**, puis **iOS certificates**, puis **Generate certificate**. Choisissez le type **Apple Distribution** et la clé `orgAnniversaire ASC`. Codemagic crée et garde le certificat.
4. Allez dans **iOS provisioning profiles**, puis **Fetch profiles**. Si aucun profil n'apparaît, créez un profil **App Store** pour `fr.organniversaire.app` sur developer.apple.com (rubrique Profiles), puis relancez Fetch.
5. Dans l'app Codemagic, choisissez **codemagic.yaml** comme configuration et lancez **Start new build** (workflow `ios-testflight`).

À chaque nouvel envoi sur `main`, Codemagic recompile l'app et l'envoie sur TestFlight. Le numéro de build augmente tout seul.

## Étape 7 : tester sur votre iPhone
1. Installez **TestFlight** depuis l'App Store sur l'iPhone.
2. Dans App Store Connect, ouvrez **TestFlight**, puis **Tests internes**, et ajoutez-vous comme testeur. L'invitation arrive par e-mail.
3. Points à vérifier :
   - connexion, puis fermeture et réouverture de l'app : vous devez rester connecté ;
   - l'autorisation des notifications ;
   - une réponse d'invité, qui doit déclencher une notification (ou le bouton « Envoyer un test » dans l'admin) ;
   - l'import des contacts et le partage ;
   - le mode avion, qui doit afficher l'écran hors ligne.

## Étape 8 : soumission à Apple
Dans la fiche de l'app (App Store Connect) :
- **Captures d'écran** :
  - iPhone 6,9" (1320×2868) obligatoires, 3 à 10 images ;
  - faites-les depuis l'app TestFlight sur votre iPhone. Les captures d'un iPhone récent 6,7"/6,9" sont acceptées.
- **Description, mots-clés, URL d'assistance** : `https://organniversaire.fr/` ;
- **URL de confidentialité** : la page de confidentialité du site.
- **Confidentialité de l'app** : déclarez **Nom, Adresse e-mail, Photos, Identifiant de l'appareil**, tous « liés à l'utilisateur » et « Fonctionnalités de l'app », et **aucun suivi**. C'est cohérent avec `PrivacyInfo.xcprivacy`.
- **Classification d'âge** : 4+.
- **Informations pour la vérification** : créez un **compte de démonstration** avec une fête et quelques invités, puis donnez l'e-mail et le mot de passe. Ajoutez cette note :
  > Application destinée aux parents qui organisent l'anniversaire de leur enfant : création de la fête, invitations, suivi des réponses avec notifications push, import des invités depuis les contacts, plan de préparation. La suppression du compte se trouve dans Profil › Zone sensible.
- Choisissez le build TestFlight, puis cliquez sur **Soumettre pour vérification**.

## Modifier l'app plus tard
La plupart des changements se font **sur le site**, et l'app les affiche aussitôt, sans nouvelle soumission.
Une nouvelle version n'est nécessaire que si vous modifiez les fichiers Swift, l'icône ou les autorisations. Dans ce cas :
1. augmentez `MARKETING_VERSION` dans `project.yml` ;
2. envoyez les fichiers sur GitHub ;
3. soumettez le nouveau build.

## Phase 2 : achat intégré
Créez d'abord les produits dans App Store Connect (**Monétisation › Achats intégrés**), un par formule payante. Je brancherai ensuite StoreKit 2 et la vérification côté serveur.
