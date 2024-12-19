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

import_dev2_s3() {
    export_dir="/tmp/s3_export"
    mkdir -p "${export_dir}"
    local localstack_docker_id
    localstack_docker_id="$(docker ps | grep matching-processor-localstack | cut -d' ' -f 1)"
    keys=(
        "memory/embedding/skill_embedding_vectors/fm.json"
        "memory/embedding/skill_embedding_vectors/hw.json"
        "memory/embedding/skill_embedding_vectors/sw.json"
        "memory/graph_raw_skills/graph_raw_skills.json"
        "memory/interpreted_skills/interpreted_skill_sentences.json"
        "memory/interpreted_skills/interpreted_skills.json"
        "memory/job_description_tags/job_description_tags.json"
        "memory/raw_skills/raw_skills.json"
    )

    # 下記は数が多すぎるのでcopy省略
    # - bucket直下のEnterprise, Candidate, MinorOccupation
    for key in "${keys[@]}"; do
        aws s3 cp s3://techkitchen-cuisine-development2/"${key}" "${export_dir}"/"${key}" --profile=dev2
        docker exec "${localstack_docker_id}" mkdir -p "/root/$(dirname "${key}")"
        docker cp "${export_dir}/${key}" "${localstack_docker_id}":/root/"${key}"
        docker exec "${localstack_docker_id}" awslocal s3 cp /root/"${key}" s3://cuisine-localstack/"${key}"
    done
}

import_dev2_mongo() {
    # dev2環境のmongoからcollectionをexportして整形
    local dev2_mongo_options
    dev2_mongo_options="--quiet --host cuisine.cluster-ch6yi0oook4r.ap-northeast-1.docdb.amazonaws.com:27017 --username gachapin --password wqkwc1LIg8SU2mhlwaRQ41YvSgjnf6bU --authenticationDatabase admin fridge"
    # 本来mongoexportでexportしたいが、dev2環境にはmongoexportがインストールされていないのでmongoで代用
    ssh gachapin_dev2_bastion mongo "${dev2_mongo_options}" --eval 'printjson\(db.candidates.find\(\).toArray\(\)\)' >/tmp/candidates.json
    ssh gachapin_dev2_bastion mongo "${dev2_mongo_options}" --eval 'printjson\(db.enterprises.find\(\).toArray\(\)\)' >/tmp/enterprises.json
    ssh gachapin_dev2_bastion mongo "${dev2_mongo_options}" --eval 'printjson\(db.minorOccupations.find\(\).toArray\(\)\)' >/tmp/minorOccupations.json
    sed -ri 's/ObjectId\((".*")\)/\1/' /tmp/candidates.json
    sed -ri 's/ObjectId\((".*")\)/\1/' /tmp/enterprises.json
    sed -ri 's/ObjectId\((".*")\)/\1/' /tmp/minorOccupations.json

    # matching-processor mongo の全コレクションを削除
    local matching_processor_docker_id
    mongo_auth_param="mongodb://gachapin:Cuisine-SandB0x@127.0.0.1:27017/fridge?authSource=admin"
    matching_processor_docker_id="$(docker ps | grep matching-processor-cuisine-matching-mongo | cut -d' ' -f 1)"
    docker exec "${matching_processor_docker_id}" mongosh "${mongo_auth_param}" --eval "db.candidates.drop()"
    docker exec "${matching_processor_docker_id}" mongosh "${mongo_auth_param}" --eval "db.enterprises.drop()"
    docker exec "${matching_processor_docker_id}" mongosh "${mongo_auth_param}" --eval "db.minorOccupations.drop()"

    # localに転送したcollectionをmatching-processorのmongoに取り込み
    docker cp "/tmp/candidates.json" "${matching_processor_docker_id}":/tmp/
    docker cp "/tmp/enterprises.json" "${matching_processor_docker_id}":/tmp/
    docker cp "/tmp/minorOccupations.json" "${matching_processor_docker_id}":/tmp/
    docker exec "${matching_processor_docker_id}" mongoimport --uri "${mongo_auth_param}" --jsonArray --collection candidates --file /tmp/candidates.json
    docker exec "${matching_processor_docker_id}" mongoimport --uri "${mongo_auth_param}" --jsonArray --collection enterprises --file /tmp/enterprises.json
    docker exec "${matching_processor_docker_id}" mongoimport --uri "${mongo_auth_param}" --jsonArray --collection minorOccupations --file /tmp/minorOccupations.json
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
# TODO: option指定時のみimportするよう調整
import_dev2_s3
import_dev2_mongo
reset_fridge_mongo
