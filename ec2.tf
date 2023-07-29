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