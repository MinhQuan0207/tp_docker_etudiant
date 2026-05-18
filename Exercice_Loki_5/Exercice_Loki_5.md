# TP Observabilité Loki — Exercice 5 : Filtrage avancé et requêtes de formatage

## Objectif
Maîtriser les filtres de ligne LogQL et reformater l'affichage des logs avec line_format.

## Commandes exécutées

```bash
docker compose up -d

# Générateur de logs HTTP
while true; do
  STATUS=$(shuf -n1 -e 200 200 200 404 500 503)
  LEVEL=$([ "$STATUS" = "200" ] && echo "info" || echo "error")
  METHOD=$(shuf -n1 -e GET POST PUT)
  PATH=$(shuf -n1 -e /api/users /api/orders /api/products)
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"level\":\"$LEVEL\",\"msg\":\"HTTP/1.1 $METHOD $PATH\",\"status\":$STATUS,\"service\":\"api\"}" >> logs/apps/access.log
  sleep 1
done
```

## Requêtes LogQL construites

```logql
# A - Filtre inclusion
{job="http-logs"} |= "HTTP/1.1"

# B - Filtre exclusion
{job="http-logs"} |= "HTTP/1.1" != `"status":200`

# C - Parser JSON
{job="http-logs"} |= "HTTP/1.1" != `"status":200` | json

# D - Reformatage line_format
{job="http-logs"} |= "HTTP/1.1" != `"status":200` | json | line_format "[{{.level | upper}}] -> {{.msg}} (status={{.status}})"
```

## Résultats observés

- [ ] Requête A retourne tous les logs HTTP/1.1
- [ ] Requête B exclut les status 200
- [ ] Requête C expose les champs JSON dans l'interface
- [ ] Requête D affiche les logs reformatés `[ERROR] -> ...`

## Difficultés rencontrées
<!-- ... -->

## Conclusion
LogQL permet de filtrer, parser et reformater les logs directement à la requête,
sans modifier les données stockées dans Loki.