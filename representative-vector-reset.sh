#!/bin/bash

set -euxo pipefail

cd "$(dirname "$0")"

reset_matching_processor_localstack() {
    local localstack_docker_id
    localstack_docker_id="$(docker ps | grep matching-processor-localstack | cut -d' ' -f 1)"

    docker exec "${localstack_docker_id}" awslocal s3 rm s3://cuisine-localstack/interval_task/representative_vector/ --recursive

    s3_upload_dest="s3://cuisine-localstack/interval_task/representative_vector/representative-vector-updated.json"
    docker cp settings/representative-vector-updated.json "${localstack_docker_id}":/root/
    docker exec "${localstack_docker_id}" awslocal s3 cp /root/representative-vector-updated.json "${s3_upload_dest}"
}

reset_fridge_mongo() {
    local fridge_docker_id
    fridge_docker_id="$(docker ps | grep "mongo.*11020" | cut -d' ' -f 1)"
    mongo_auth_param="mongodb://gachapin:Cuisine-SandB0x@127.0.0.1:27017/fridge?authSource=admin"

    local collection_dir
    collection_dir="/home/tom/ghq/github.com/gachapin-pj/cuisine/matching-processor/tests/document_db"
    # fridgeのDBの全collectionを一度削除
    docker exec "${fridge_docker_id}" mongosh "${mongo_auth_param}" --eval "db.candidates.deleteMany({})"
    docker exec "${fridge_docker_id}" mongosh "${mongo_auth_param}" --eval "db.enterprises.deleteMany({})"
    docker exec "${fridge_docker_id}" mongosh "${mongo_auth_param}" --eval "db.minorOccupations.deleteMany({})"
    # fridgeのmongoを、matching-processorのmongo初期化に使用するjsonを使用して初期化
    docker cp "${collection_dir}/candidates.json" "${fridge_docker_id}":/tmp/
    docker cp "${collection_dir}/enterprises.json" "${fridge_docker_id}":/tmp/
    docker cp "${collection_dir}/minor_occupations.json" "${fridge_docker_id}":/tmp/
    docker exec "${fridge_docker_id}" mongoimport --uri "${mongo_auth_param}" --collection candidates --file /tmp/candidates.json --jsonArray
    docker exec "${fridge_docker_id}" mongoimport --uri "${mongo_auth_param}" --collection enterprises --file /tmp/enterprises.json --jsonArray
    docker exec "${fridge_docker_id}" mongoimport --uri "${mongo_auth_param}" --collection minorOccupations --file /tmp/minor_occupations.json --jsonArray

    # 念のために代表vector全削除
    docker exec "${fridge_docker_id}" mongosh "${mongo_auth_param}" --eval "db.minorOccupations.updateMany({},{ \$set: {representativeVectors:[]}})"
    docker exec "${fridge_docker_id}" mongosh "${mongo_auth_param}" --eval "db.enterprises.updateMany({},{ \$set: {representativeVectors:[]}})"
    docker exec "${fridge_docker_id}" mongosh "${mongo_auth_param}" --eval "db.candidates.updateMany({},{ \$set: {representativeVectors:[]}})"
}

reset_matching_processor_localstack
reset_fridge_mongo
