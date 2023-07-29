resource "aws_iam_role" "ecs_task" {
    for_each           = toset(["ecsTaskExecutionRole", "ecsTaskRole"])
    name               = each.value
    assume_role_policy = <<-EOS
    {
      "Version": "2008-10-17",
      "Statement": [
          {
              "Sid": "",
              "Effect": "Allow",
              "Principal": {
                  "Service": "ecs-tasks.amazonaws.com"
              },
              "Action": "sts:AssumeRole"
          }
      ]
    }
    EOS
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
    role       = aws_iam_role.ecs_task["ecsTaskExecutionRole"].name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy_attachment" "ecs_task" {
    role       = aws_iam_role.ecs_task["ecsTaskRole"].name
    policy_arn = "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientReadWriteAccess"
}