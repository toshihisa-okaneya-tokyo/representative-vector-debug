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
    local matching_processor_docker_id
    local fridge_docker_id
    matching_processor_docker_id="$(docker ps | grep matching-processor-cuisine-matching-mongo | cut -d' ' -f 1)"
    fridge_docker_id="$(docker ps | grep "mongo.*11020" | cut -d' ' -f 1)"
    mongo_auth_param="mongodb://gachapin:Cuisine-SandB0x@127.0.0.1:27017/fridge?authSource=admin"

    # エクスポート用ディレクトリ
    export_dir="/tmp/matching_processor_export"
    mkdir -p "${export_dir}"

    # matching-processor の mongo からデータをエクスポート
    # 出力先を/tmpにするとpermission deniedになるときがあるので/root/配下に出力
    docker exec "${matching_processor_docker_id}" mongoexport --uri "${mongo_auth_param}" --collection candidates --out /root/candidates.json
    docker exec "${matching_processor_docker_id}" mongoexport --uri "${mongo_auth_param}" --collection enterprises --out /root/enterprises.json
    docker exec "${matching_processor_docker_id}" mongoexport --uri "${mongo_auth_param}" --collection minorOccupations --out /root/minor_occupations.json

    # エクスポートしたファイルをホストにコピー
    docker cp "${matching_processor_docker_id}:/root/candidates.json" "${export_dir}/candidates.json"
    docker cp "${matching_processor_docker_id}:/root/enterprises.json" "${export_dir}/enterprises.json"
    docker cp "${matching_processor_docker_id}:/root/minor_occupations.json" "${export_dir}/minor_occupations.json"

    # fridge の DB の全コレクションを削除
    docker exec "${fridge_docker_id}" mongosh "${mongo_auth_param}" --eval "db.candidates.deleteMany({})"
    docker exec "${fridge_docker_id}" mongosh "${mongo_auth_param}" --eval "db.enterprises.deleteMany({})"
    docker exec "${fridge_docker_id}" mongosh "${mongo_auth_param}" --eval "db.minorOccupations.deleteMany({})"

    # fridge にデータをインポート
    docker cp "${export_dir}/candidates.json" "${fridge_docker_id}":/tmp/
    docker cp "${export_dir}/enterprises.json" "${fridge_docker_id}":/tmp/
    docker cp "${export_dir}/minor_occupations.json" "${fridge_docker_id}":/tmp/
    docker exec "${fridge_docker_id}" mongoimport --uri "${mongo_auth_param}" --collection candidates --file /tmp/candidates.json
    docker exec "${fridge_docker_id}" mongoimport --uri "${mongo_auth_param}" --collection enterprises --file /tmp/enterprises.json
    docker exec "${fridge_docker_id}" mongoimport --uri "${mongo_auth_param}" --collection minorOccupations --file /tmp/minor_occupations.json

    # 念のために代表vector全削除
    docker exec "${fridge_docker_id}" mongosh "${mongo_auth_param}" --eval "db.minorOccupations.updateMany({},{ \$set: {representativeVectors:[]}})"
    docker exec "${fridge_docker_id}" mongosh "${mongo_auth_param}" --eval "db.enterprises.updateMany({},{ \$set: {representativeVectors:[]}})"
    docker exec "${fridge_docker_id}" mongosh "${mongo_auth_param}" --eval "db.candidates.updateMany({},{ \$set: {representativeVectors:[]}})"
}

reset_matching_processor_localstack
reset_fridge_mongo
