#!/bin/bash
set -euo pipefail

image=${1:?Usage: deploy-textbook-library IMAGE@sha256:DIGEST}
if [[ ! "$image" =~ ^[a-z0-9_-]+/textbook-library@sha256:[a-f0-9]{64}$ ]]; then
    echo "Expected a Docker Hub textbook-library image digest." >&2
    exit 1
fi

exec 9>/var/lock/textbook-library-deploy.lock
flock -w 60 9

network=textbook-library
mongo_image=mongo:7.0
docker pull "$image"
docker network inspect "$network" >/dev/null 2>&1 || docker network create "$network"
if docker container inspect textbook-mongo >/dev/null 2>&1; then
    docker start textbook-mongo >/dev/null
else
    docker run -d --name textbook-mongo --network "$network" --restart unless-stopped \
        --mount source=textbook-library-mongo,target=/data/db "$mongo_image"
fi

mongo_ready() {
    docker exec textbook-mongo mongosh --quiet \
        --eval 'quit(db.adminCommand({ping: 1}).ok === 1 ? 0 : 1)' >/dev/null 2>&1
}

for attempt in {1..30}; do
    if mongo_ready; then break; fi
    sleep 2
done
mongo_ready
docker run --rm --network "$network" --entrypoint mongoimport \
    --mount type=bind,source=/opt/textbook-library/textbooks_data.json,target=/seed.json,readonly \
    "$mongo_image" --uri=mongodb://textbook-mongo:27017/superData \
    --collection=textbooks --file=/seed.json --jsonArray --mode=upsert --stopOnError

if docker container inspect textbook-app-previous >/dev/null 2>&1; then
    if ! docker container inspect textbook-app >/dev/null 2>&1; then
        docker rename textbook-app-previous textbook-app
        docker start textbook-app
    else
        docker rm -f textbook-app-previous
    fi
fi

if docker container inspect textbook-app >/dev/null 2>&1; then
    docker rename textbook-app textbook-app-previous
    docker stop textbook-app-previous
fi

verify_app() {
    curl -fsS --max-time 5 http://127.0.0.1:3001/actuator/health |
        jq -e '.status == "UP"' >/dev/null &&
    curl -fsS --max-time 5 http://127.0.0.1:3001/textbook \
        -H 'Content-Type: application/json' -d '{"id":0}' |
        jq -e 'select(.id == 0 and .author == "Ian Sommerville") | {id, name, author}'
}

if docker run -d --name textbook-app --network "$network" --restart unless-stopped \
    -p 127.0.0.1:3001:3001 -e MONGO_URI=mongodb://textbook-mongo:27017/superData \
    "$image"; then
    for attempt in {1..30}; do
        if verify_app; then
            docker inspect --format 'Deployed {{.Config.Image}}' textbook-app
            if docker container inspect textbook-app-previous >/dev/null 2>&1; then
                docker rm textbook-app-previous
            fi
            exit 0
        fi
        sleep 2
    done
fi

docker logs --tail 30 textbook-app >&2 || true
docker rm -f textbook-app >/dev/null 2>&1 || true
if docker container inspect textbook-app-previous >/dev/null 2>&1; then
    docker rename textbook-app-previous textbook-app
    docker start textbook-app
fi
echo "Deployment failed the application or textbook lookup check." >&2
exit 1
