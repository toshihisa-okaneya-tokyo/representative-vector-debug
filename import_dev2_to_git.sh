#!/bin/bash

set -euxo pipefail

# TODO: primeurはgit登録しても100GB超えているためにgithubにpush出来ない。対応検討
export_primeur() {
    MYSQL_PASSWORD=JHwl1rGjT8GEWHh0LZQQ2Bj9fb1PzQva
    ssh gachapin_dev2_bastion <<EOF

# DML出力 (mysqldumpを実行してパスワードはコンソール履歴に残さずに入力)
echo "Enter MySQL password for primeur user:"
mysqldump -u primeur -p'${MYSQL_PASSWORD}' -h primeur-db.ch6yi0oook4r.ap-northeast-1.rds.amazonaws.com primeur -P 3306 -t > /tmp/dml.sql

# DDL出力
echo "Enter MySQL password for primeur user:"
mysqldump -u primeur -p'${MYSQL_PASSWORD}' -h primeur-db.ch6yi0oook4r.ap-northeast-1.rds.amazonaws.com primeur -P 3306 -d > /tmp/ddl.sql

EOF

    scp gachapin_dev2_bastion:/tmp/dml.sql /home/tom/ghq/github.com/gachapin-pj/cuisine/vector-update/mysql-docker-init/
    scp gachapin_dev2_bastion:/tmp/ddl.sql /home/tom/ghq/github.com/gachapin-pj/cuisine/vector-update/mysql-docker-init/
}

export_mongo() {
    # dev2環境のmongoからcollectionをexportして整形
    local dev2_mongo_options
    dev2_mongo_options="--quiet --host cuisine.cluster-ch6yi0oook4r.ap-northeast-1.docdb.amazonaws.com:27017 --username gachapin --password wqkwc1LIg8SU2mhlwaRQ41YvSgjnf6bU --authenticationDatabase admin fridge"
    # 本来mongoexportでexportしたいが、dev2環境にはmongoexportがインストールされていないのでmongoで代用
    ssh gachapin_dev2_bastion mongo "${dev2_mongo_options}" --eval 'printjson\(db.candidates.find\(\).toArray\(\)\)' >/tmp/candidates.json
    ssh gachapin_dev2_bastion mongo "${dev2_mongo_options}" --eval 'printjson\(db.enterprises.find\(\).toArray\(\)\)' >/tmp/enterprises.json
    ssh gachapin_dev2_bastion mongo "${dev2_mongo_options}" --eval 'printjson\(db.minorOccupations.find\(\).toArray\(\)\)' >/tmp/minor_occupations.json
    sed -ri 's/ObjectId\((".*")\)/\1/' /tmp/candidates.json
    sed -ri 's/ObjectId\((".*")\)/\1/' /tmp/enterprises.json
    sed -ri 's/ObjectId\((".*")\)/\1/' /tmp/minor_occupations.json
    cp /tmp/candidates.json /home/tom/ghq/github.com/gachapin-pj/cuisine/matching-processor/tests/document_db/
    cp /tmp/candidates.json /home/tom/ghq/github.com/gachapin-pj/cuisine/fridge/tests/mock/documentDB/
    cp /tmp/enterprises.json /home/tom/ghq/github.com/gachapin-pj/cuisine/matching-processor/tests/document_db/
    cp /tmp/enterprises.json /home/tom/ghq/github.com/gachapin-pj/cuisine/fridge/tests/mock/documentDB/
    cp /tmp/minor_occupations.json /home/tom/ghq/github.com/gachapin-pj/cuisine/matching-processor/tests/document_db/
    cp /tmp/minor_occupations.json /home/tom/ghq/github.com/gachapin-pj/cuisine/fridge/tests/mock/documentDB/
}

export_s3_memories() {
    s3_keys=(
        memory/raw_skills/raw_skills.json
        memory/job_description_tags/job_description_tags.json
        memory/interpreted_skills/interpreted_skills.json
        memory/interpreted_skills/interpreted_skill_sentences.json
        memory/graph_raw_skills/graph_raw_skills.json
        memory/embedding/skill_embedding_vectors/sw.json
        memory/embedding/skill_embedding_vectors/hw.json
        memory/embedding/skill_embedding_vectors/fm.json
    )
    for s3_key in "${s3_keys[@]}"; do
        aws s3 cp "s3://techkitchen-cuisine-development2/${s3_key}" "/home/tom/ghq/github.com/gachapin-pj/cuisine/matching-processor/tests/s3/${s3_key}" --profile=dev2
    done
}

import_to_vector_update() {
    cd /home/tom/ghq/github.com/gachapin-pj/cuisine/vector-update
    make down
    docker rmi vector-update-cuisine-vector-update-rdb || true

    cd /home/tom/ghq/github.com/gachapin-pj/cuisine/vector-update
    make ci
}

import_to_matching_processor() {
    cd /home/tom/ghq/github.com/gachapin-pj/cuisine/matching-processor
    make down
    docker rmi matching-processor-localstack || true
    docker rmi matching-processor-cuisine-matching-mongo || true
    docker volume rm -f matching-processor_mongodb_data
    cd /home/tom/ghq/github.com/gachapin-pj/cuisine/matching-processor
    make ci
}

IMPORT_ENABLED=false
while getopts "i" opt; do
    case $opt in
    i)
        IMPORT_ENABLED=true
        ;;
    *)
        echo "Usage: $0 [-i]"
        exit 1
        ;;
    esac
done

export_primeur
export_s3_memories
export_mongo

if [ "$IMPORT_ENABLED" = true ]; then
    import_to_vector_update
    import_to_matching_processor
fi

echo "処理が完了しました。"
