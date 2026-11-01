terraform {
  backend "s3" {
    #bucket = "sctp-tfstate-ce13"
    bucket = "sctp-core-tfstate"
    key    = "tk/group2-tk-github-oidc-bootstrap.tfstate"
    #region = "us-east-1"
    region = "ap-southeast-1"
  }
}