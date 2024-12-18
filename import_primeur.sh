#!/bin/bash

set -euxo pipefail

MYSQL_PASSWORD=JHwl1rGjT8GEWHh0LZQQ2Bj9fb1PzQva

# 1. SSH接続
ssh gachapin_dev2_bastion <<EOF

# 2. DML出力 (mysqldumpを実行してパスワードはコンソール履歴に残さずに入力)
echo "Enter MySQL password for primeur user:"
mysqldump -u primeur -p'${MYSQL_PASSWORD}' -h primeur-db.ch6yi0oook4r.ap-northeast-1.rds.amazonaws.com primeur -P 3306 -t > /tmp/dml.sql

# 3. DDL出力
echo "Enter MySQL password for primeur user:"
mysqldump -u primeur -p'${MYSQL_PASSWORD}' -h primeur-db.ch6yi0oook4r.ap-northeast-1.rds.amazonaws.com primeur -P 3306 -d > /tmp/ddl.sql

EOF

# 4. ローカルにファイルを転送
scp gachapin_dev2_bastion:/tmp/dml.sql /home/tom/ghq/github.com/gachapin-pj/cuisine/vector-update/mysql-docker-init/
scp gachapin_dev2_bastion:/tmp/ddl.sql /home/tom/ghq/github.com/gachapin-pj/cuisine/vector-update/mysql-docker-init/

# 5. Dockerイメージの削除
cd /home/tom/ghq/github.com/gachapin-pj/cuisine/vector-update
make down
docker rmi vector-update-cuisine-vector-update-rdb

# 6. CI処理を実行して、localstackにjsonを出力
make ci && make up
vector_update_docker_id=$(docker ps -a | grep cuisine/cuisine-vector-update | cut -d' ' -f 1)
docker logs "${vector_update_docker_id}" -f

# 7. localstackからjsonを転送
mkdir -p /tmp/vector_update_localstack/
vector_update_localstack_docker_id=$(docker ps | grep vector-update-localstack | cut -d' ' -f 1)
docker exec -it "${vector_update_localstack_docker_id}" awslocal s3 cp s3://vector-update-localstack/ /tmp/vector_update_localstack/ --recursive
docker cp "${vector_update_localstack_docker_id}":/tmp/vector_update_localstack/ /tmp/

# 8. matching-processorのlocalstackにjsonを取り込む
matching_processor_localstack_id=$(docker ps | grep matching-processor-localstack | cut -d' ' -f 1)
docker exec -it "${matching_processor_localstack_id}" awslocal s3 rm s3://cuisine-localstack/memory/ --recursive
docker exec -it "${matching_processor_localstack_id}" awslocal s3 rm s3://cuisine-localstack/MinorOccupation/ --recursive
docker cp /tmp/vector_update_localstack/ "${matching_processor_localstack_id}":/tmp/
docker exec -it "${matching_processor_localstack_id}" awslocal s3 sync /tmp/vector_update_localstack/ s3://cuisine-localstack/

# 最後にメッセージを表示
echo "処理が完了しました。"
