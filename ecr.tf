# ECR repository
resource "aws_ecr_repository" "this" {
  name         = var.image_name
  force_delete = true
}

# Push Docker image
resource "null_resource" "push_image" {
    triggers = {
      image_name = var.image_name
      image_tag  = var.image_tag
    }
    # docker login
    provisioner "local-exec" {
        command = "aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${var.account_id}.dkr.ecr.${var.region}.amazonaws.com"
    }
    # docker tag
    provisioner "local-exec" {
        command = "docker tag ${var.image_name}:${var.image_tag} ${aws_ecr_repository.this.repository_url}:${var.image_tag}"
    }
    # docker push
    provisioner "local-exec" {
        command = "docker push ${aws_ecr_repository.this.repository_url}:${var.image_tag}"
    }
}