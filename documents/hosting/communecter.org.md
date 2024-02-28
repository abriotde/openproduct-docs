
# Etude de Besoin

Voici les besoins que j'ai dans l'ordre de priorité.

1) Une page d'authentification/création de compte avec tout ce que cela comporte : vérification du mail, système en cas de perte de login/mdp...

2) Une page de création/édition du profil de producteur correspondant au mail d'authentiication (Ou au téléphone si vous savez faire). Un profil comporte :
- Un nom d'entreprise (à défaut "nom" d'une personne physique)
- Un email avec l'autorisation ou nom de l'avertir une fois par mois maximum (email, option sendEmail=ENUM(Yes, Never))
- Un site web (webSite)
- Un numéro de téléphone (phoneNumber & phoneNumber2)
- Une description de 1000 caractères maximum (`text`)
- Une description simple qui correspond au métier/activité (shortDescription). Exp : Jeux en bois, Ebéniste, Vannerie...
- Code postale (postCode)
- Ville (City)
- Adresse sans le code postal ni la ville (address)
- Latitude
- Longitude
Les champs sont obligatoires par défaut mais
- L'email ou le site web ou le téléphone peuvent être vide mais au moins 2 doivent être remplis (Si c'est trop complexe, les mettre optionnels).
- La lattitude/longitude peuvent être déduits de l'adresse et vice versa donc un seul des 2 suffit (Si c'est trop complexe demander que l'adresse). ("https://api-adresse.data.gouv.fr/reverse/", "https://api-adresse.data.gouv.fr/search/")
- Une liste de production disponible.
- Des tags de catégories dont la liste est disponible ici https://openproduct.fr/data/categories.json.
- Une liste de produits dont la liste, non exhaustive est disponible ici https://openproduct.fr/data/produces_fr.json.

3) Une page de création/modication de profil de producteur par tous avec un tag du créateur du profil. Actuellement je le renseigne dans noteModeration, j'aime utiliser geoprecision pour dire le degré de fiabilité du producteur (1 dans le cas 2, 0.5 dans le cas 3 (celui-ci) par exemple).

4) Un plus serait de pouvoir laisser un commentaire "Anonyme" sur un producteur idéalement même avec un pouce pour confirmer. Ainsi on pourrait aller rechercher les commentaires très marqués pour intervenir. Peut-être plus qu'un commentaire qui est lourd en modération, une case à cocher : "Producteur qui n'existe plus", "Information érronnées sur ce producteur", "Faux producteur (Il exerce mais ne produit pas vraiment)", "Autre". On entends par commentaire anonyme que je pense qu'il n'est pas bon de laisser le pseudo du commentateur mais qu'en iterne on doit garder si possible qui a fait ce commentaire.

Pour information, voici les champs que j'ai en interne dans la table producer : 
id, latitude, longitude, name, firstname, lastname, city, postCode, address, siret, phoneNumber, phoneNumber2, email, sendEmail, website, websiteStatus, status, `text`, produces, wikiTitle, wikiDefaultTitle, shortDescription, openingHours, categories, geoprecision, nbMailSend, nbModeration, noteModeration, preferences, tokenAccess 

PS : Actuellement la liste de produits est en développement dans la branche "filter".

# Proposition de contrat

- 10% de mes revenus jusqu'à 2 000 euros constant (augmenté de l'inflation) + 50 euros par ans pour l'hébergement toujours en euros constants. Attention cela correspond à un plafond ce qui veut dire que je ne garanti pas de pouvoir vous les verser un jour. Mais c'est le maximum que je puisse faire.
- Une mention de votre partenariat sur https://openproduct.fr/hall-of-fame.html (La page n'est pas encore mise en évidence car elle n'est pas remplie.) Je pourrais éventuellement vous mettre sur la page d'accueil.
