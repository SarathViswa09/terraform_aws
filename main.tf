terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = ">= 5.34.0"

    }
  }
}
provider "aws" {
  region = "us-east-1"
}

# workflow:

# 1. Create s3 bucket
# 2. Create admin user for transform family
# 3. Assign policy attachment for transfer family and then create keys

# 4. Create a role for IAM
# 5. Role policy for s3 (for IAM)

# 7. Create transfer family server
# 8. create TF user and assingn bucket to the user
# 9. ssh communication setup

# 10. Create a lambda function
# 11. assign iam role and policy attachments
# 12. Give permissions to lambda to be invoked after change in s3
# 13. Add some files from local to s3
# 14. finally call lambda function whenever there is addition of new file to s3

resource "aws_s3_bucket" "test_bucket" {
  bucket = "sarath-transfer-family-bucket"
  force_destroy  = true
}

resource "aws_iam_user" "admin_for_transfer_family" {
  name = var.user1_name
}

resource "aws_iam_access_key" "admin_access_key" {
  user = aws_iam_user.admin_for_transfer_family.name
}

resource "aws_iam_user_policy_attachment" "policy_attachment_for_tf" {
  policy_arn = "arn:aws:iam::aws:policy/AWSTransferFullAccess"
  user = aws_iam_user.admin_for_transfer_family.name
}

resource "aws_iam_role" "transfer_family_role" {
  name = "TransferFamilyRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "transfer.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "role_policy_for_s3" {
  name = "transfer-s3-access"
  role = aws_iam_role.transfer_family_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:ListBucket"],
        Resource = aws_s3_bucket.test_bucket.arn
      },
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
        Resource = "${aws_s3_bucket.test_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_transfer_server" "transfer_server_sftp" {
  identity_provider_type = "SERVICE_MANAGED"
  endpoint_type = "PUBLIC"
  protocols = ["SFTP"]
}

resource "aws_transfer_user" "tf_user" {
  user_name = var.tf_user
  role = "arn:aws:iam::${var.acc_id}:role/${aws_iam_role.transfer_family_role.name}"
  server_id = aws_transfer_server.transfer_server_sftp.id

}

resource "aws_transfer_ssh_key" "ssh_key" {
  server_id = aws_transfer_server.transfer_server_sftp.id
  user_name = aws_transfer_user.tf_user.user_name
  body      = trimspace(var.ssh_public_key)
}

resource "aws_iam_role" "lambda_auto" {
  name = "lambda_automation"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_auto.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "s3_trigger" {
  filename = var.file_name
  function_name = "tf_files_automation"
  runtime = "python3.13"
  role = aws_iam_role.lambda_auto.arn
  handler = "lambda_function.lambda_handler"
}

resource "aws_lambda_permission" "s3_lambda_invoke" {
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_trigger.function_name
  principal = "s3.amazonaws.com"
  source_arn = aws_s3_bucket.test_bucket.arn
}

locals {
  files = fileset("${path.module}/test_files", "*")
}

resource "aws_s3_bucket_object" "name" {
  for_each = toset(local.files)
  bucket = aws_s3_bucket.test_bucket.id
  key = each.value
  source = "${path.module}/test_files/${each.value}"
}

resource "aws_s3_bucket_notification" "s3_lambda_trigger" {
  bucket = aws_s3_bucket.test_bucket.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_trigger.arn
    events = ["s3:ObjectCreated:*"]
  }
  depends_on = [
    aws_lambda_permission.s3_lambda_invoke
  ]
}