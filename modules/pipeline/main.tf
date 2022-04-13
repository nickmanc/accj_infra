provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "codepipeline_bucket" {
  force_destroy = true #happy for logs to be destroyed by terraform?
  bucket = "${var.fqdn}.codepipeline"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "CodePipelineBucketEncryption" {
  bucket = aws_s3_bucket.codepipeline_bucket.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "CodePipelineVersioning" {
  bucket = aws_s3_bucket.codepipeline_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "CodePipelineBucketPublicAccessBlock" {
  bucket                  = aws_s3_bucket.codepipeline_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "CodePipelineBucketPolicy" {
  bucket = aws_s3_bucket.codepipeline_bucket.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowSSLRequestsOnly",
        "Action" : "s3:*",
        "Effect" : "Deny",
        "Resource" : [
          aws_s3_bucket.codepipeline_bucket.arn,
          "${aws_s3_bucket.codepipeline_bucket.arn}/*"
        ],
        "Condition" : {
          "Bool" : {
            "aws:SecureTransport" : "false"
          }
        },
        "Principal" : "*"
      }
    ]
  })
}

resource "aws_s3_bucket_acl" "codepipeline_bucket_acl" {
  bucket = aws_s3_bucket.codepipeline_bucket.id
  acl    = "private"
}

resource "aws_iam_role" "codepipeline_role" {
  name = "test-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline_policy"
  role = aws_iam_role.codepipeline_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:PutObjectAcl",
        "s3:PutObject"
      ],
      "Resource": [
        "${aws_s3_bucket.codepipeline_bucket.arn}",
        "${aws_s3_bucket.codepipeline_bucket.arn}/*",
        "${var.ContentBucketArn}",
        "${var.ContentBucketArn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codestar-connections:UseConnection"
      ],
      "Resource": "${var.GithubCodestarConnectionArn}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}


resource "aws_codepipeline" "codepipeline" {
  name     = "accj-s3-deploy"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      category         = "Source"
      configuration    = {
        "BranchName"           = "main"
        "ConnectionArn"        = var.GithubCodestarConnectionArn
        "FullRepositoryId"     = var.GitHubRepositoryId
        "OutputArtifactFormat" = "CODE_ZIP"
      }
      input_artifacts  = []
      name             = "Source"
      namespace        = "SourceVariables"
      output_artifacts = [
        "SourceArtifact",
      ]
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      region           = var.region
      run_order        = 1
      version          = "1"
    }
  }
  stage {
    name = "Deploy"

    action {
      category         = "Deploy"
      configuration    = {
        "BucketName" = var.ContentBucket
        "Extract"    = "true"
      }
      input_artifacts  = [
        "SourceArtifact",
      ]
      name             = "Deploy"
      namespace        = "DeployVariables"
      owner            = "AWS"
      provider         = "S3"
      region           = var.region
      run_order        = 1
      version          = "1"
    }
  }
}