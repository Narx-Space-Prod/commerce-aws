resource "aws_kms_key" "notifications" {
  description             = "Encrypt CloudWatch alarm notifications for the learning session"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "EnableAccountIAM", Effect = "Allow", Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }, Action = "kms:*", Resource = "*" },
    { Sid       = "CloudWatchAlarms", Effect = "Allow", Principal = { Service = "cloudwatch.amazonaws.com" }, Action = ["kms:Decrypt", "kms:GenerateDataKey*"], Resource = "*",
      Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
    }
  ] })
}
resource "aws_sns_topic_policy" "alarms" {
  arn = aws_sns_topic.operations.arn
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Service = "cloudwatch.amazonaws.com" }, Action = "sns:Publish", Resource = aws_sns_topic.operations.arn,
    Condition = {
      StringEquals = { "aws:SourceAccount" = var.account_id },
      ArnLike      = { "aws:SourceArn" = "arn:aws:cloudwatch:${var.region}:${var.account_id}:alarm:${var.name}-*" }
    }
  }] })
}
