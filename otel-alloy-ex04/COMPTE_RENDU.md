# Compte Rendu — Exercice 4 : Pipeline, processors et hot reload

**Date :** 2026-06-10
**Auteur :** mqnguyen
**Durée effective :** ~30 min
**Section TP :** Fondamentaux

---

## Objectif

Étendre la pipeline Alloy avec deux processors (`batch` et `attributes`) chaînés entre
le receiver OTLP et l'exporteur debug, vérifier l'injection automatique de l'attribut
`deployment.environment=lab` sur les 3 signaux, puis recharger la configuration à chaud
sans redémarrer le pod Alloy.

---

## Environnement

| Élément | Valeur |
|---|---|
| Cluster | kind `otel-lab` |
| Namespace Alloy | `observability` |
| Pod Alloy | `alloy-2sljb` (DaemonSet, AGE stable tout au long de l'exercice) |
| Helm chart | `grafana/alloy` |
| Révisions Helm appliquées | 3 → 4 → 5 |

---

## Arborescence du dossier

```
~/tp-observabilite/otel-alloy-ex04/
└── alloy-values.yaml    ← configuration Alloy avec processors batch + attributes
```

---

## Concepts clés abordés

### Pipeline Alloy avec processors chaînés

La pipeline finale est composée de 4 composants câblés en séquence :

```
otelcol.receiver.otlp "default"
         │
         ▼
otelcol.processor.batch "default"
         │
         ▼
otelcol.processor.attributes "default"
         │
         ▼
otelcol.exporter.debug "default"
```

Chaque composant déclare explicitement ses sorties (`output`) vers le composant suivant
via `[otelcol.processor.batch.default.input]`. C'est la spécificité d'Alloy par rapport
au Collector OTel classique : les connexions sont explicites et visibles dans l'UI.

### otelcol.processor.batch

Regroupe les signaux reçus en lots avant de les transmettre au composant suivant.
Avantages : réduction du nombre d'appels réseau, meilleure compression, moins de
charge CPU. Visible dans les logs : plusieurs spans arrivent groupés dans le même
`ResourceSpans` (jusqu'à 8 spans par lot observé).

### otelcol.processor.attributes

Modifie les attributs des signaux en transit. L'action `insert` ajoute l'attribut
seulement s'il n'existe pas déjà (contrairement à `update` qui écraserait la valeur
existante). S'applique aux 3 signaux (traces, métriques, logs) simultanément.

### Hot reload Alloy

Alloy surveille son ConfigMap Kubernetes. Quand `helm upgrade` met à jour le ConfigMap,
Alloy détecte le changement et recharge la configuration automatiquement sans redémarrage
du pod. Le endpoint `http://localhost:12345/-/reload` permet de forcer un rechargement
immédiat depuis l'extérieur du pod (via port-forward).

> Note : `wget` et `curl` sont absents de l'image Alloy (image minimaliste).
> Le reload depuis l'intérieur du conteneur doit passer par le port-forward :
> `curl -s -X POST http://localhost:12345/-/reload` depuis la VM.

---

## Fichier alloy-values.yaml

```yaml
alloy:
  extraArgs:
    - --stability.level=experimental

  extraPorts:
    - name: otlp-grpc
      port: 4317
      targetPort: 4317
      protocol: TCP
    - name: otlp-http
      port: 4318
      targetPort: 4318
      protocol: TCP

  configMap:
    content: |
      otelcol.receiver.otlp "default" {
        grpc { endpoint = "0.0.0.0:4317" }
        http { endpoint = "0.0.0.0:4318" }
        output {
          metrics = [otelcol.processor.batch.default.input]
          logs    = [otelcol.processor.batch.default.input]
          traces  = [otelcol.processor.batch.default.input]
        }
      }

      otelcol.processor.batch "default" {
        output {
          metrics = [otelcol.processor.attributes.default.input]
          logs    = [otelcol.processor.attributes.default.input]
          traces  = [otelcol.processor.attributes.default.input]
        }
      }

      otelcol.processor.attributes "default" {
        action {
          key    = "deployment.environment"
          value  = "lab"
          action = "insert"
        }
        output {
          metrics = [otelcol.exporter.debug.default.input]
          logs    = [otelcol.exporter.debug.default.input]
          traces  = [otelcol.exporter.debug.default.input]
        }
      }

      otelcol.exporter.debug "default" {
        verbosity = "detailed"
      }
```

---

## Commandes exécutées

### 1. Création du fichier de valeurs

```bash
cat > alloy-values.yaml << 'ENDOFFILE'
# ... (contenu ci-dessus)
ENDOFFILE
```

> Utiliser `ENDOFFILE` comme délimiteur heredoc plutôt que `EOF` pour éviter
> les conflits avec les blocs de code internes.

### 2. Déploiement via Helm upgrade

```bash
helm upgrade alloy grafana/alloy   --namespace observability   --values alloy-values.yaml
# Résultat : Release "alloy" has been upgraded. REVISION: 3
```

### 3. Vérification du pod

```bash
kubectl -n observability get pods
# NAME          READY   STATUS    RESTARTS   AGE
# alloy-2sljb   2/2     Running   0          44m
```

### 4. Génération de trafic depuis l'app demo

```bash
pkill -f "kubectl port-forward" 2>/dev/null && sleep 1
kubectl port-forward svc/demo 5000:5000 &
sleep 2
for i in $(seq 1 20); do curl -s http://localhost:5000/ > /dev/null; done
```

### 5. Vérification de l'attribut dans les logs Alloy

```bash
kubectl -n observability logs daemonset/alloy --tail=100 | \
  grep "deployment.environment" | head -5
```

### 6. Test du hot reload (modifier la valeur)

```bash
sed -i 's/value  = "lab"/value  = "lab-v2"/' alloy-values.yaml

helm upgrade alloy grafana/alloy \
  --namespace observability \
  --values alloy-values.yaml
# Résultat : REVISION: 4

# Reload via port-forward (depuis la VM, pas depuis le conteneur)
curl -s -X POST http://localhost:12345/-/reload
```

---

## Résultats observés

### Attribut injecté sur les 3 signaux

| Signal | Attribut observé | Valeur |
|---|---|---|
| **Traces** (ResourceSpans) | `deployment.environment` | `Str(lab)` |
| **Logs** (ResourceLog) | `deployment.environment` | `Str(lab)` |
| **Métriques** (ResourceMetrics) | `deployment.environment` | `Str(lab)` |

### Extrait — Trace avec deployment.environment

```
ResourceSpans #0
Resource attributes:
  -> service.name: Str(demo)
Span #0
  Name : GET /
  Attributes:
    -> http.method: Str(GET)
    -> http.status_code: Int(200)
    -> deployment.environment: Str(lab)    ← injecté par processor.attributes
```

### Bonus — Métriques Flask + Exemplars

Les métriques générées automatiquement par l'instrumentation Flask incluent :

- `http.server.active_requests` — nombre de requêtes HTTP en cours (type Sum)
- `http.server.duration` — histogramme de latence en ms (35 requêtes 200 OK, 3 requêtes 500)

Les métriques portent des **Exemplars** : liens directs entre un point de métrique
et la trace qui l'a produit. Exemple observé :

```
Exemplar #0
  -> Trace ID: 71abd0c89d0b5e348212506576a7dc81
  -> Span ID:  5e7d8b9278e09172
  -> Value:    66ms
```

C'est la corrélation métriques ↔ traces : depuis un pic de latence dans Grafana,
on peut naviguer directement vers la trace exacte qui l'a causé.

---

## Problèmes rencontrés

### cat << 'EOF' coupé dans le terminal

**Cause :** Le bloc de configuration contenait des caractères spéciaux qui ont
interrompu le heredoc lors du copier-coller dans le terminal.

**Solution :** Utiliser un délimiteur différent (`ENDOFFILE`) et écrire le fichier
via un éditeur (`nano`/`vim`) ou un fichier téléchargé.

### wget/curl absents dans le conteneur Alloy

**Cause :** L'image Alloy est minimaliste et ne contient pas ces outils.

**Solution :** Déclencher le reload depuis la VM via le port-forward actif :
```bash
curl -s -X POST http://localhost:12345/-/reload
```
En pratique, `helm upgrade` suffit car Alloy recharge automatiquement son ConfigMap.

---

## Conclusion

La pipeline Alloy enrichie avec `processor.batch` et `processor.attributes` est
fonctionnelle. L'attribut `deployment.environment=lab` est bien injecté sur les
3 signaux sans modifier l'application.

**Points clés retenus :**

- Les connexions entre composants Alloy sont explicites (`output` → `input`) et visibles dans l'UI graphique `:12345`
- `processor.batch` regroupe les signaux en lots, réduisant la charge réseau
- `processor.attributes` avec `action = "insert"` ajoute un attribut sans écraser les valeurs existantes
- Le hot reload Alloy se déclenche automatiquement après `helm upgrade` (mise à jour du ConfigMap)
- `curl -s -X POST http://localhost:12345/-/reload` force un rechargement immédiat depuis l'extérieur du pod
- Les Exemplars OTel permettent la corrélation métriques ↔ traces sans code supplémentaire

L'exercice 5 portera sur l'export vers un vrai backend (Tempo, Loki, Prometheus/Mimir).
