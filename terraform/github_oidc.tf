# Lets GitHub Actions assume an AWS role for the duration of a single deploy
# run, instead of a long-lived AWS key sitting in repo secrets (see README
# for why). Scoped to this repo only, and only when the workflow is running
# on main - PRs never get to assume this role.

data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]
}

resource "aws_iam_role" "github_actions_deploy" {
  name = "padillacastillo-github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github_actions.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:padillacastillo/padillacastillo:ref:refs/heads/master"
        }
      }
    }]
  })
}

# Scoped to the resources this project actually owns, all named with a
# "padillacastillo-" prefix. A few services (ACM, Route 53, CloudFront,
# API Gateway, SES) don't get a resource-level ARN until after they're first
# created, so those are left at "*" - not fully least-privilege, but this
# role still can't touch anything outside this account's own resources for
# those services, and it's a solo-owned account.
resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "deploy-padillacastillo-site"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Terraform's aws_s3_bucket resource reads/writes a long tail of
        # sub-resources on refresh (ACLs, versioning, encryption, policy,
        # public-access-block, ...) - scoping to discrete actions here turns
        # into permission whack-a-mole, so this is scoped by bucket name
        # instead, to every bucket this project owns (state + site).
        Sid      = "SiteAndStateBuckets"
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = ["arn:aws:s3:::padillacastillo-*", "arn:aws:s3:::padillacastillo-*/*"]
      },
      {
        Sid      = "CloudFront"
        Effect   = "Allow"
        Action   = "cloudfront:*"
        Resource = "*"
      },
      {
        Sid      = "ACM"
        Effect   = "Allow"
        Action   = "acm:*"
        Resource = "*"
      },
      {
        Sid      = "Route53"
        Effect   = "Allow"
        Action   = "route53:*"
        Resource = "*"
      },
      {
        Sid      = "ApiGateway"
        Effect   = "Allow"
        Action   = "apigateway:*"
        Resource = "*"
      },
      {
        Sid      = "Lambda"
        Effect   = "Allow"
        Action   = "lambda:*"
        Resource = "arn:aws:lambda:*:*:function:padillacastillo-*"
      },
      {
        Sid      = "DynamoDB"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "arn:aws:dynamodb:*:*:table/padillacastillo-*"
      },
      {
        Sid      = "SecretsManager"
        Effect   = "Allow"
        Action   = "secretsmanager:*"
        Resource = "arn:aws:secretsmanager:*:*:secret:padillacastillo-*"
      },
      {
        Sid      = "SES"
        Effect   = "Allow"
        Action   = "ses:*"
        Resource = "*"
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = "logs:*"
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/padillacastillo-*"
      },
      {
        # DescribeLogGroups is a list-style call that AWS doesn't let you
        # scope down to a specific log group ARN, so it has to stay on "*" -
        # it's read-only (just lists names/metadata), so low risk.
        Sid      = "LogsList"
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "*"
      },
      {
        # Only the two Lambda execution roles - deliberately excludes this
        # role itself, so a compromised deploy run can't grant itself
        # broader access.
        Sid    = "LambdaExecutionRoles"
        Effect = "Allow"
        Action = [
          "iam:GetRole", "iam:CreateRole", "iam:DeleteRole", "iam:TagRole",
          "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:ListRoleTags", "iam:PassRole",
        ]
        Resource = "arn:aws:iam::*:role/padillacastillo-*-lambda"
      },
      {
        # This Terraform config also manages the OIDC provider itself, so
        # the role needs to read/update it - scoped to OIDC-provider-only
        # actions, never anything that could touch this role's own trust
        # policy or permissions.
        Sid    = "GithubOidcProvider"
        Effect = "Allow"
        Action = [
          "iam:GetOpenIDConnectProvider", "iam:CreateOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint", "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider", "iam:ListOpenIDConnectProviders",
          "iam:AddClientIDToOpenIDConnectProvider",
        ]
        Resource = "*"
      },
    ]
  })
}

output "github_actions_role_arn" {
  description = "Add this as the AWS_ROLE_ARN repo variable in GitHub (Settings > Secrets and variables > Actions > Variables)"
  value       = aws_iam_role.github_actions_deploy.arn
}
