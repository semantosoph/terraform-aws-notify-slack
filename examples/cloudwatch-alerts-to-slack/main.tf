provider "aws" {
  region = "eu-west-1"
}

resource "aws_kms_key" "this" {
  description = "KMS key for notify-slack test"
}

# Encrypt the URL, storing encryption here will show it in logs and in tfstate
# https://www.terraform.io/docs/state/sensitive-data.html
resource "aws_kms_ciphertext" "slack_url" {
  plaintext = "https://hooks.slack.com/services/AAA/BBB/CCC"
  key_id    = aws_kms_key.this.arn
}

module "notify_slack" {
  source = "../../"

  for_each = toset([
    "develop",
    "release",
    "test",
  ])

  sns_topic_name                        = "slack-topic"
  enable_sns_topic_delivery_status_logs = true

  # Specify the ARN of the pre-defined feedback role or leave blank to have the module create it
  #sns_topic_lambda_feedback_role_arn = "arn:aws:iam::111122223333:role/sns-delivery-status"

  lambda_function_name = "notify_slack_${each.value}"

  slack_webhook_url = aws_kms_ciphertext.slack_url.ciphertext_blob
  slack_channel     = "aws-notification"
  slack_username    = "reporter"

  kms_key_arn = aws_kms_key.this.arn

  lambda_description = "Lambda function which sends notifications to Slack"

  # VPC
  #  lambda_function_vpc_subnet_ids = module.vpc.intra_subnets
  #  lambda_function_vpc_security_group_ids = [module.vpc.default_security_group_id]

  tags = {
    Name = "cloudwatch-alerts-to-slack"
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "NotifySlackDuration"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Average"
  threshold           = "5000"
  alarm_description   = "Duration of notifying slack exceeds threshold"

  alarm_actions = [module.notify_slack["develop"].slack_topic_arn]

  dimensions = {
    FunctionName = module.notify_slack["develop"].notify_slack_lambda_function_name
  }
}

######
# VPC
######
resource "random_pet" "this" {
  length = 2
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = random_pet.this.id
  cidr = "10.10.0.0/16"

  azs           = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  intra_subnets = ["10.10.101.0/24", "10.10.102.0/24", "10.10.103.0/24"]
}
