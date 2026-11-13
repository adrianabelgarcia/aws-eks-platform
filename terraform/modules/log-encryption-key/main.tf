data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# CloudWatch Logs needs an explicit grant on a customer managed key. The
# encryption-context condition scopes that grant to log groups in this
# account and region only.
data "aws_iam_policy_document" "key" {
  #checkov:skip=CKV_AWS_111: The write statement is for the CloudWatch Logs service principal only and is constrained by kms:EncryptionContext:aws:logs:arn. KMS key policies scope resources to this key.
  statement {
    sid    = "EnableAccountRootAdministration"
    effect = "Allow"
    # Administrative actions only (no kms:Encrypt/Decrypt for the root user).
    # Without this statement the key becomes unmanageable if the IAM role that
    # created it is deleted, so it must stay.
    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
    ]
    #checkov:skip=CKV_AWS_109: KMS key policy resource "*" refers only to this key. The statement grants key administration to the account root, the standard lockout-safe pattern.
    #checkov:skip=CKV_AWS_356: KMS key policy resource "*" refers only to this key, not to every key in the account.
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogsUse"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}

resource "aws_kms_key" "logs" {
  description             = "CloudWatch Logs encryption for ${var.name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.key.json
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${var.name}-logs"
  target_key_id = aws_kms_key.logs.key_id
}
