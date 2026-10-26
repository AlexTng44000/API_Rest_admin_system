# Réponses aux questions : 
# PARTIE 1
## 1.1 `dapi GET /version | jq`
### Version 26.1.4  
### API version 1.45  
> HTTP 200
{
  "Platform": {
    "Name": "Docker Engine - Community"
  },
  "Components": [
    {
      "Name": "Engine",
      "Version": "26.1.4",
      "Details": {
        "ApiVersion": "1.45",
        "Arch": "amd64",
        "BuildTime": "2024-06-05T11:29:19.000000000+00:00",
        "Experimental": "false",
        "GitCommit": "de5c9cf",
        "GoVersion": "go1.21.11",
        "KernelVersion": "6.8.9-100.fc38.x86_64",
        "MinAPIVersion": "1.24",
        "Os": "linux"
      }
    },
    {
      "Name": "containerd",
      "Version": "1.6.33",
      "Details": {
        "GitCommit": "d2d58213f83a351ca8f528a95fbd145f5654e957"
      }
    },
    {
      "Name": "runc",
      "Version": "1.1.12",
      "Details": {
        "GitCommit": "v1.1.12-0-g51d5e94"
      }
    },
    {
      "Name": "docker-init",
      "Version": "0.19.0",
      "Details": {
        "GitCommit": "de40ad0"
      }
    }
  ],
  "Version": "26.1.4",
  "ApiVersion": "1.45",
  "MinAPIVersion": "1.24",
  "GitCommit": "de5c9cf",
  "GoVersion": "go1.21.11",
  "Os": "linux",
  "Arch": "amd64",
  "KernelVersion": "6.8.9-100.fc38.x86_64",
  "BuildTime": "2024-06-05T11:29:19.000000000+00:00"
}  

## 1.2 `dapi GET /info | jq '{ Containers, ContainersRunning, Images, OperatingSystem, NCPU }'`
> HTTP 200
{
  "Containers": 9,
  "ContainersRunning": 2,
  "Images": 16,
  "OperatingSystem": "Fedora Linux 38 (Workstation Edition)",
  "NCPU": 12
}

## 1.3 `dapi GET /info | jq '(.MemTotal / 1024 / 1024 / 1024) | round'`
> HTTP 200
15
## 1.4 `dapi GET '/containers/json?all=true' | jq -r '.[] | "\(.Names[0] | ltrimstr("/")) : \(.State) : \(.Image)"'`
> HTTP 200
mangatrack-redis : running : redis:7-alpine
mangatrack-postgres : running : postgres:17-alpine
tp_note-sleeper-1 : exited : tp_note-sleeper
tp_note-database-1 : exited : postgres:17-alpine
focused_babbage : exited : hello-world
mysql-app-1 : exited : mysql-app
mysql-mysql-1 : exited : mysql:8.4
test-docker-tp : exited : sha256:cd576a79134ef51184f9c31e621f565e8a418efbf23ae2201d84695d0097f948
tender_euclid : exited : nginx:otel

## 1.5  `dapi GET /images/json | jq '(map(.Size) | add // 0) / 1024 / 1024 | round'`
> HTTP 200
2237
# Liste des tags des images
> `dapi GET /images/json | jq -r '.[].RepoTags[]?`  
> HTTP 200
redis:7-alpine
multistage-app:latest
cache-test:v1
ghcr.io/alextng44000/docker-tp:latest
mysql-app:latest
mon-app:latest
mysql:8.4
nginx:1.31-otel
nginx:otel
nginx:latest
postgres:17-alpine
tp_note-sleeper:latest
alpine:latest
hello-world:latest

# PARTIE 2
## 2.2 `dapi POST '/containers/create?name=web-tp1' "$BODY" | jq`
> HTTP 201
{
  "Id": "5a5892974c7968d8ff577a1952cbb3d0fe8cf849ebd58bef044e0e11ecff4f61",
  "Warnings": []
}
### Deuxième exécution
> HTTP 409
{
  "message": "Conflict. The container name \"/web-tp1\" is already in use by container \"5a5892974c7968d8ff577a1952cbb3d0fe8cf849ebd58bef044e0e11ecff4f61\". You have to remove (or rename) that container to be able to reuse that name."
}

## 2.3 `dapi POST /containers/web-tp1/start`

**Première exécution :**

> HTTP 204

Le conteneur démarre. L'API ne renvoie pas de corps, aucune information supplémentaire n'est nécessaire.

**Deuxième exécution :**

> HTTP 304

Le conteneur est déjà en cours d'exécution. Docker ne le démarre donc pas une deuxième fois.

## 2.5 `dapi DELETE /containers/web-tp1`
> {"message":"cannot remove container \"/web-tp1\": container is running: stop the container before removing or force remove"}
HTTP 409  

Le code 409 indique que la suppression est impossible car le conteneur est encore en cours d'exécution. 
Ce n'est pas une erreur de requête (400) ni un problème d'autorisation (403), mais un conflit avec l'état actuel du conteneur.

## 2.6 `dapi POST '/containers/web-tp1/stop?t=5'`
**Première exécution :**
> HTTP 204

**Deuxième exécution :**
> HTTP 304

t veut dire le temps et est égal a 5s

## 2.7 `dapi DELETE /containers/web-tp1`

> HTTP 204

### Vérification après suppression

`dapi GET /containers/web-tp1/json | jq`

> HTTP 404
{
  "message": "No such container: web-tp1"
}

Le conteneur a été supprimé. Docker renvoie une erreur 404 car il ne retrouve plus le conteneur.

# PARTIE 3
## 3.1 — Exécuter une commande

**Commande qui fonctionne :**

`nginx -v; head -n 2 /etc/os-release`

HTTP 200 — ExitCode : 0

**Commande qui échoue :**

`ls /nexiste-pas`

HTTP 200 — ExitCode : 1

Le code HTTP 200 indique que l'appel à l'API Docker a fonctionné, même lorsque la commande exécutée échoue. Le code de sortie permet de savoir si la commande a réussi (0) ou échoué (1).

## 3.2 — Lire les logs

**Code HTTP :** 200

Les huit premiers octets sont `01 00 00 00 00 00 00 5a`

Ils correspondent à un en-tête Docker. Le premier octet (`01`) indique que les données viennent de stdout. Les quatre derniers (`00 00 00 5a`) indiquent une taille de 90 octets.

Cet en-tête n'apparaît pas dans la partie 3.1 car on a utilisé `Tty: true`, ce qui permet de récupérer directement la sortie de la commande sans cet en-tête.


## Tableau récapitulatif des codes HTTP — Partie 2

| Étape | Requête | Code HTTP | Signification |
|---|---|---|---|
| 2.1 | `POST /images/create` | 200 | Image téléchargée |
| 2.2 | `POST /containers/create` | 201 | Conteneur créé |
| 2.2 bis | Même requête une seconde fois | 409 | Nom du conteneur déjà utilisé |
| 2.3 | `POST /containers/{id}/start` | 204 | Conteneur démarré |
| 2.3 bis | Même requête une seconde fois | 304 | Conteneur déjà démarré |
| 2.5 | `DELETE /containers/{id}` | 409 | Impossible de supprimer un conteneur en marche |
| 2.6 | `POST /containers/{id}/stop` | 204 | Conteneur arrêté |
| 2.6 bis | Même requête une seconde fois | 304 | Conteneur déjà arrêté |
| 2.7 | `DELETE /containers/{id}` | 204 | Conteneur supprimé |
| 2.7 bis | `GET /containers/{id}/json` | 404 | Conteneur introuvable après suppression |
| 3.1 | `POST /exec/{id}/start` | 200 | Appel API réussi, mais commande échouée (ExitCode : 1) |