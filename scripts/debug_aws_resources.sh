#!/bin/bash

# debug_aws_resources.sh
# This script provides debugging information for AWS S3 buckets, CloudFront distributions, and ACM certificates.

# Function to check if AWS CLI is installed
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo "AWS CLI is not installed. Please install it to use this script."
        exit 1
    fi
}

# Function to get S3 bucket details
get_s3_bucket_info() {
    local bucket_name=$1
    echo "Fetching details for S3 bucket: $bucket_name"

    # Get bucket ACL
    echo "Bucket ACL:"
    aws s3api get-bucket-acl --bucket "$bucket_name"

    # Get bucket policy
    echo "Bucket Policy:"
    aws s3api get-bucket-policy --bucket "$bucket_name" || echo "No bucket policy found."

    # Get bucket location
    echo "Bucket Location:"
    aws s3api get-bucket-location --bucket "$bucket_name"

    # Get bucket website configuration
    echo "Bucket Website Configuration:"
    aws s3api get-bucket-website --bucket "$bucket_name" || echo "No website configuration found."

    echo "-------------------------------------------"
}

# Function to get CloudFront distribution details
get_cloudfront_info() {
    echo "Fetching details for CloudFront distributions"

    # List all distributions and extract relevant details
    aws cloudfront list-distributions --query "DistributionList.Items[*].{Id:Id, DomainName:DomainName, Origins:Origins.Items[*].DomainName}" --output table

    echo "-------------------------------------------"
}

# Function to get ACM certificate details
get_acm_certificate_info() {
    echo "Fetching details for ACM certificates"

    # List all certificates
    certificate_arns=$(aws acm list-certificates --query "CertificateSummaryList[*].CertificateArn" --output text)

    for cert_arn in $certificate_arns; do
        echo "Details for Certificate ARN: $cert_arn"
        aws acm describe-certificate --certificate-arn "$cert_arn" --query "Certificate.{DomainName:DomainName, Status:Status, IssuedAt:IssuedAt, NotAfter:NotAfter}" --output table
    done

    echo "-------------------------------------------"
}

# Main script execution
check_aws_cli

echo "Starting AWS resources debugging..."

# Debug S3 Buckets
echo "Enter S3 bucket names to debug (space-separated):"
read -r bucket_names
for bucket in $bucket_names; do
    get_s3_bucket_info "$bucket"
done

# Debug CloudFront Distributions
get_cloudfront_info

# Debug ACM Certificates
get_acm_certificate_info

echo "AWS resources debugging completed."
