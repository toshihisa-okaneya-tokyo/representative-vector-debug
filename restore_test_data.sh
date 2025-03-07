#!/bin/bash

set -euxo pipefail

# MPのlocalstackは docker-compose down するとs3が再作成されてしまうので注意。再作成後に作成直後の不十分な状態のs3が読まれる
matching_processor_localstack_docker_id=$(sudo docker ps | grep matching-processor-localstack | cut -d' ' -f 1)
docker cp /home/tom/test_mongo_s3_backup/s3/ "${matching_processor_localstack_docker_id}:/root/"
docker exec "${matching_processor_localstack_docker_id}" awslocal s3 rm s3://cuisine-localstack/ --recursive
docker exec "${matching_processor_localstack_docker_id}" awslocal s3 cp /root/s3/MinorOccupation/ s3://cuisine-localstack/MinorOccupation/ --recursive
docker exec "${matching_processor_localstack_docker_id}" awslocal s3 cp /root/s3/interval_task/ s3://cuisine-localstack/interval_task/ --recursive
docker exec "${matching_processor_localstack_docker_id}" awslocal s3 cp /root/s3/memory/ s3://cuisine-localstack/memory/ --recursive
