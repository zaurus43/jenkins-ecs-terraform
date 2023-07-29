# jenkins-ecs-terraform
『[Amazon ECS 入門ハンズオン](https://catalog.us-east-1.prod.workshops.aws/workshops/7ffc4ed9-d4b3-44dc-bade-676162b427cd/ja-JP)』を参考に、TerraformでJenkinsをECS上に構築する

## 実行環境
- MacBook Air (M1, 2020)
- macOS Ventura 13.3
- Terraform v1.5.4

## メモ
- tfstateはS3上で管理する. [backendはTerraformで管理しないほうがいい](https://developer.hashicorp.com/terraform/language/settings/backends/s3)ためCLIで作成する.
    > Terraform is an administrative tool that manages your infrastructure, and so ideally the infrastructure that is used by Terraform should exist outside of the infrastructure that Terraform manages.
    
    [Terraformで、同じ構成を複数プロビジョニングしたい: backend-configオプション編](https://dev.classmethod.jp/articles/multiple-provisionings-with-terraform-backend-config-option/) を参考に `config.s3.tfbackend` を以下のように設定する.

    ```config.s3.tfbackend
    bucket = "jenkins-dev-tfstate"
    key    = "terraform.tfstate"
    region = "ap-northeast-1"
    ```
    以下のコマンドで設定値をもとにS3バケットを作成し、バージョニングを有効化する.
    > Warning! It is highly recommended that you enable Bucket Versioning on the S3 bucket to allow for state recovery in the case of accidental deletions and human error.
    https://developer.hashicorp.com/terraform/language/settings/backends/s3
    ```bash
    % BUCKET=`cat ./config.s3.tfbackend | grep bucket | sed "s/^bucket = \"\(.*\)\"$/\1/"`
    % REGION=`cat ./config.s3.tfbackend | grep region | sed "s/^region = \"\(.*\)\"$/\1/"`
    ```
    バケット作成
    ```bash
    % aws s3api create-bucket \
        --bucket $BUCKET \
        --region $REGION \
        --create-bucket-configuration LocationConstraint=$REGION
    ```
    バージョニングを有効化
    ```bash
    % aws s3api put-bucket-versioning \
        --bucket $BUCKET \
        --versioning-configuration Status=Enabled
    ```


- [JenkinsのDockerイメージ](https://hub.docker.com/r/jenkins/jenkins) を取得する. Apple M1チップの場合、`arm64` アーキテクチャ用のDockerイメージを取得すると、ECSのデプロイ時に下記のエラーで止まってしまうため、`x86-64` アーキテクチャを指定して取得する. 
    > exec /usr/bin/tini: exec format error 

    ```bash
    % docker pull jenkins/jenkins:lts-jdk11 --platform linux/amd64
    ```

- ALBのヘルスチェックパスを、ハンズオンの設定のまま `/` にしていると、Jenkinsの初回起動時の認証画面で、ALBのヘルスチェックがUnhealthyになる. [起動に成功していれば `/login` で `200` が返ってくる](https://stackoverflow.com/questions/66900744/aws-alb-health-check-failure)のでそのように設定した.

    ```hcl
    health_check = {
        enabled             = true
        interval            = 30
        path                = "/login"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        healthy_threshold   = 5
        unhealthy_threshold = 2
        matcher             = "200"
    }
    ```

- [jenkinsの設定を永続化するために、ハンズオンの構成にEFSを追加する.](https://2357-gi.medium.com/2020%E5%B9%B4%E3%81%ABjenkins%E3%82%92aws%E4%B8%8A%E3%81%A7%E5%8B%95%E3%81%8B%E3%81%99%E9%81%B8%E6%8A%9E%E8%82%A2%E3%81%A8%E3%81%97%E3%81%A6ecs%E3%82%92%E5%BC%B7%E3%81%8F%E6%8E%A8%E3%81%97%E3%81%9F%E3%81%84-72c7d508c84b) 参考ページにあるように、jenkins Master node は並列稼働を許さないので、タスク希望数は `1` 、最小ヘルス率 `0%`、最大率 `100%` に設定した.

    ```hcl
    desired_count                      = 1
    deployment_minimum_healthy_percent = 0
    deployment_maximum_percent         = 100
    ```

    また、何もせずにEFSをマウントすると、タスクに権限がなく書き込みに失敗するため、以下のように何かしら対策が必要である. 

    - 事前にEC2などからマウントして、権限を変更する
    - EFSのアクセスポイントを利用する
    - コンテナに特権付与する

    コンテナに特権付与する方法は、セキュリティ面から非推奨であり、[FARGATEモードでは特権付与ができないようになっている.](https://aws.amazon.com/jp/blogs/news/building-container-images-on-amazon-ecs-on-aws-fargate/) 
    
    EC2を利用する方法は、[rootディレクトリを直接マウントする場合などに有効](https://qiita.com/sakai00kou/items/3ee37db9eb31a726f558)とのこと. 今回利用する場合は、以下のように `ec2.tf` を作成し、user_dataで起動時コマンドを設定して権限設定ができる. 

    ```hcl
    resource "aws_instance" "this"{
    ami                         = "ami-08c84d37db8aafe00" #Amazon Linux 2023
    instance_type               = "t2.micro"
    availability_zone           = module.vpc.azs[0]
    vpc_security_group_ids      = [module.vpc.default_security_group_id]
    subnet_id                   = module.vpc.public_subnets[0]
    associate_public_ip_address = "true"
    tags = {
        Name                    = "${var.project}-${var.environment}-chmodefs"
    }
    user_data                   = <<EOF
    #!/bin/bash
    EFS_MOUNT_OPTION=nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport
    EFS_MOUNT_POINT=/efs

    sudo yum -y install nfs-utils ;

    sudo mkdir $EFS_MOUNT_POINT
    sudo mount -t nfs4 -o $EFS_MOUNT_OPTION ${module.efs.dns_name}:/ $EFS_MOUNT_POINT

    sudo mkdir $EFS_MOUNT_POINT/jenkins_home
    sudo chmod 777 $EFS_MOUNT_POINT/jenkins_home
    EOF
    }
    ```

    今回は、ホスト側の `/jenkins_home` に `jenkins` ユーザーで書き込みができるようにしたいので、そのようにアクセスポイントを設定する方法が最も適していそう. EFSの作成には[公式モジュール](https://github.com/terraform-aws-modules/terraform-aws-efs)を利用したので、`efs.tf` に `jenkins_home`という名前で設定した. 

    ```hcl
    access_points = {
        jenkins_home = {
            name                     = "jenkins_home"
            posix_user = {
                gid                  = 1000
                uid                  = 1000
            }
            root_directory = {
                path                 = "/jenkins_home"
                creation_info = {
                owner_gid            = 1000
                owner_uid            = 1000
                permissions          = "755"
                }
            }
        }
    }
    ```
    作成したアクセスポイントは `module.efs.access_points["jenkins_home"]` で取得できるので、`ecr.tf` で以下のように `volume` ブロックを設定する. 
    ```hcl
    volume {
        name = "jenkins_home"
        efs_volume_configuration {
            file_system_id           = module.efs.id
            transit_encryption       = "ENABLED"
            authorization_config {
                access_point_id      = module.efs.access_points["jenkins_home"].id
                iam                  = "ENABLED"
            }
        }
    }
    ```
    上記に加えてECSのタスクに [EFSアクセスポイントをマップする権限を付与するIAMロールを作成する.](https://aws.amazon.com/jp/blogs/news/developers-guide-to-using-amazon-efs-with-amazon-ecs-and-aws-fargate-part-3/) アタッチするポリシーは `AmazonElasticFileSystemClientReadWriteAccess` を利用した.


## 参考
- [Amazon ECS 入門ハンズオンの環境をTerraformで作成する](https://hi1280.hatenablog.com/entry/2023/04/07/200303)
- [Running Jenkins jobs in AWS ECS with slave agents](https://jenkinshero.com/jenkins-jobs-in-aws-ecs-with-slave-agents/)