#!/bin/bash

# quickpage.sh - Quick S3/CloudFront/SSL deployment script
# Usage: ./quickpage.sh yourdomain.com [options]

set -e

# Parse command line arguments
DOMAIN=""
WEBSITE_DIR="./website"
SKIP_CERT=false
SKIP_CERT_VALIDATION=true
SKIP_S3=true
SKIP_UPLOAD=true
SKIP_CLOUDFRONT=false
REGION="us-east-1"
BUCKET_REGION="eu-central-1"
CERT_ARN=""
# Parse command-line arguments
DEBUG=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --debug) DEBUG=true ;;
        # Add other options here
    esac
    shift
done

if $DEBUG; then
    ./scripts/debug_aws_resources.sh
    exit
fi

function show_usage {
    echo "Usage: ./quickpage.sh [options] yourdomain.com"
    echo ""
    echo "Options:"
    echo "  --website-dir DIR       Directory containing website files (default: ./website)"
    echo "  --skip-cert             Skip certificate creation"#!/bin/bash

# quickpage.sh - Quick S3/CloudFront/SSL deployment script
# Usage: ./quickpage.sh yourdomain.com [options]

set -e

# Parse command line arguments
DOMAIN=""
WEBSITE_DIR="./website"
SKIP_CERT=false
SKIP_CERT_VALIDATION=false
SKIP_S3=false
SKIP_UPLOAD=false
SKIP_CLOUDFRONT=false
SKIP_CUSTOM_DOMAIN=false
REGION="us-east-1"
BUCKET_REGION="eu-central-1"
CERT_ARN=""

function show_usage {
    echo "Usage: ./quickpage.sh [options] yourdomain.com"
    echo ""
    echo "Options:"
    echo "  --website-dir DIR       Directory containing website files (default: ./website)"
    echo "  --skip-cert             Skip certificate creation"
    echo "  --skip-cert-validation  Skip waiting for certificate validation"
    echo "  --skip-custom-domain    Create CloudFront without custom domain (use if cert not validated)"
    echo "  --cert-arn ARN          Use existing certificate ARN" 
    echo "  --skip-s3               Skip S3 bucket creation"
    echo "  --skip-upload           Skip uploading files to S3"
    echo "  --skip-cloudfront       Skip CloudFront distribution creation"
    echo "  --region REGION         Region for ACM and CloudFront (default: us-east-1)"
    echo "  --bucket-region REGION  Region for S3 bucket (default: eu-central-1)"
    echo "  --help                  Show this help message"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --website-dir)
            WEBSITE_DIR="$2"
            shift 2
            ;;
        --skip-cert)
            SKIP_CERT=true
            shift
            ;;
        --skip-cert-validation)
            SKIP_CERT_VALIDATION=true
            shift
            ;;
        --skip-custom-domain)
            SKIP_CUSTOM_DOMAIN=true
            shift
            ;;
        --cert-arn)
            CERT_ARN="$2"
            SKIP_CERT=true
            shift 2
            ;;
        --skip-s3)
            SKIP_S3=true
            shift
            ;;
        --skip-upload)
            SKIP_UPLOAD=true
            shift
            ;;
        --skip-cloudfront)
            SKIP_CLOUDFRONT=true
            shift
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --bucket-region)
            BUCKET_REGION="$2"
            shift 2
            ;;
        --help)
            show_usage
            ;;
        *)
            if [[ -z $DOMAIN ]]; then
                DOMAIN="$1"
                shift
            else
                echo "ERROR: Unknown option $1"
                show_usage
            fi
            ;;
    esac
done

# Check if domain is provided
if [[ -z $DOMAIN ]]; then
    echo "ERROR: Domain name is required"
    show_usage
fi

echo "========================================================"
echo "🌍 QuickPage: Deploying $DOMAIN"
echo "========================================================"

# Step 1: Create or use existing SSL Certificate
if [[ $SKIP_CERT == false ]]; then
    echo "🔒 Step 1/4: Checking for existing certificates for $DOMAIN..."
    
    # Check if there's an existing certificate for this domain
    EXISTING_CERT_ARN=$(aws acm list-certificates --region $REGION \
        --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn" \
        --output text)
    
    if [[ -n $EXISTING_CERT_ARN ]]; then
        # Check if the certificate is valid and issued
        CERT_STATUS=$(aws acm describe-certificate --certificate-arn "$EXISTING_CERT_ARN" \
            --region $REGION --query "Certificate.Status" --output text)
        
        if [[ $CERT_STATUS == "ISSUED" ]]; then
            echo "✅ Found existing valid certificate for $DOMAIN"
            echo "Certificate ARN: $EXISTING_CERT_ARN"
            CERT_ARN=$EXISTING_CERT_ARN
        elif [[ $CERT_STATUS == "PENDING_VALIDATION" ]]; then
            echo "⏳ Found pending certificate for $DOMAIN that needs validation"
            echo "Certificate ARN: $EXISTING_CERT_ARN"
            CERT_ARN=$EXISTING_CERT_ARN
            
            # Get validation info for the pending certificate
            VALIDATION_INFO=$(aws acm describe-certificate \
                --certificate-arn "$CERT_ARN" \
                --region $REGION \
                --query "Certificate.DomainValidationOptions[0].ResourceRecord")
            
            VALIDATION_NAME=$(echo $VALIDATION_INFO | jq -r '.Name')
            VALIDATION_VALUE=$(echo $VALIDATION_INFO | jq -r '.Value')
            
            echo "📝 DNS Validation Required - Create this CNAME record:"
            echo "Name:  $VALIDATION_NAME"
            echo "Value: $VALIDATION_VALUE"
            echo ""
            echo "⚠️  ADD THIS TO YOUR DNS PROVIDER BEFORE CONTINUING"
            echo ""
            
            if [[ $SKIP_CERT_VALIDATION == true ]]; then
                echo "⚠️ Skipping validation wait as requested. CloudFront distribution will be created but won't work until certificate is validated."
                echo "ℹ️ You can check certificate status later with: aws acm describe-certificate --certificate-arn $CERT_ARN --region $REGION --query Certificate.Status"
            else
                read -p "Press Enter once you've added the CNAME record (or type 'skip' to proceed without waiting for validation)... " RESPONSE
                
                if [[ "${RESPONSE,,}" == "skip" ]]; then
                    echo "⚠️ Skipping validation wait. CloudFront distribution will be created but won't work until certificate is validated."
                    echo "ℹ️ You can check certificate status later with: aws acm describe-certificate --certificate-arn $CERT_ARN --region $REGION --query Certificate.Status"
                else
                    echo "⏳ Waiting for certificate validation (this may take several minutes)..."
                    aws acm wait certificate-validated --certificate-arn "$CERT_ARN" --region $REGION
                    echo "✅ Certificate validated successfully!"
                fi
            fi
        else
            echo "⚠️ Found existing certificate for $DOMAIN but status is: $CERT_STATUS"
            echo "Creating a new certificate instead..."
            EXISTING_CERT_ARN=""
        fi
    fi
    
    if [[ -z $EXISTING_CERT_ARN ]]; then
        echo "🔒 Creating new SSL Certificate in ACM..."
        CERT_ARN=$(aws acm request-certificate \
            --domain-name $DOMAIN \
            --validation-method DNS \
            --region $REGION \
            --query CertificateArn --output text)
        
        echo "✅ Certificate requested: $CERT_ARN"
        echo ""
        echo "📝 DNS Validation Required - Create this CNAME record:"
        
        # Wait briefly for the certificate to be created and validation info available
        sleep 5
        
        VALIDATION_INFO=$(aws acm describe-certificate \
            --certificate-arn "$CERT_ARN" \
            --region $REGION \
            --query "Certificate.DomainValidationOptions[0].ResourceRecord")
        
        VALIDATION_NAME=$(echo $VALIDATION_INFO | jq -r '.Name')
        VALIDATION_VALUE=$(echo $VALIDATION_INFO | jq -r '.Value')
        
        echo "Name:  $VALIDATION_NAME"
        echo "Value: $VALIDATION_VALUE"
        echo ""
        echo "⚠️  ADD THIS TO YOUR DNS PROVIDER BEFORE CONTINUING"
        echo ""
        
        read -p "Press Enter once you've added the CNAME record... " 
        
        echo "⏳ Waiting for certificate validation (this may take several minutes)..."
        aws acm wait certificate-validated --certificate-arn "$CERT_ARN" --region $REGION
        echo "✅ Certificate validated successfully!"
    fi
elif [[ -z $CERT_ARN ]]; then
    echo "❓ No certificate ARN provided. Checking for existing certificates..."
    
    # Check if there's an existing certificate for this domain
    EXISTING_CERT_ARN=$(aws acm list-certificates --region $REGION \
        --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn" \
        --output text)
    
    if [[ -n $EXISTING_CERT_ARN ]]; then
        # Check if the certificate is valid and issued
        CERT_STATUS=$(aws acm describe-certificate --certificate-arn "$EXISTING_CERT_ARN" \
            --region $REGION --query "Certificate.Status" --output text)
        
        if [[ $CERT_STATUS == "ISSUED" ]]; then
            echo "✅ Found existing valid certificate for $DOMAIN"
            echo "Certificate ARN: $EXISTING_CERT_ARN"
            CERT_ARN=$EXISTING_CERT_ARN
        elif [[ $CERT_STATUS == "PENDING_VALIDATION" ]]; then
            echo "⏳ Found pending certificate for $DOMAIN that needs validation"
            echo "Certificate ARN: $EXISTING_CERT_ARN"
            CERT_ARN=$EXISTING_CERT_ARN
            
            # Get validation info for the pending certificate
            VALIDATION_INFO=$(aws acm describe-certificate \
                --certificate-arn "$CERT_ARN" \
                --region $REGION \
                --query "Certificate.DomainValidationOptions[0].ResourceRecord")
            
            VALIDATION_NAME=$(echo $VALIDATION_INFO | jq -r '.Name')
            VALIDATION_VALUE=$(echo $VALIDATION_INFO | jq -r '.Value')
            
            echo "📝 DNS Validation Required - Create this CNAME record:"
            echo "Name:  $VALIDATION_NAME"
            echo "Value: $VALIDATION_VALUE"
            echo ""
            echo "⚠️  ADD THIS TO YOUR DNS PROVIDER BEFORE CONTINUING"
            echo ""
            
            read -p "Press Enter once you've added the CNAME record (or type 'skip' to proceed without waiting for validation)... " RESPONSE
            
            if [[ "${RESPONSE,,}" == "skip" ]]; then
                echo "⚠️ Skipping validation wait. CloudFront distribution will be created but won't work until certificate is validated."
                echo "ℹ️ You can check certificate status later with: aws acm describe-certificate --certificate-arn $CERT_ARN --region $REGION --query Certificate.Status"
            else
                echo "⏳ Waiting for certificate validation (this may take several minutes)..."
                aws acm wait certificate-validated --certificate-arn "$CERT_ARN" --region $REGION
                echo "✅ Certificate validated successfully!"
            fi
        else
            echo "⚠️ Found existing certificate for $DOMAIN but status is: $CERT_STATUS"
            echo "Please provide a valid certificate with --cert-arn or remove --skip-cert"
            exit 1
        fi
    else
        echo "❓ No existing certificates found for $DOMAIN"
        echo "Please provide a certificate ARN with --cert-arn or remove --skip-cert"
        exit 1
    fi
else
    echo "🔄 Using provided certificate: $CERT_ARN"
fi

# Step 2: Create S3 Bucket
if [[ $SKIP_S3 == false ]]; then
    echo ""
    echo "🪣 Step 2/4: Creating S3 Bucket..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket $DOMAIN 2>/dev/null; then
        echo "⚠️ Bucket already exists, skipping creation"
    else
        if [[ $BUCKET_REGION == "us-east-1" ]]; then
            aws s3api create-bucket \
                --bucket $DOMAIN \
                --region $BUCKET_REGION
        else
            aws s3api create-bucket \
                --bucket $DOMAIN \
                --region $BUCKET_REGION \
                --create-bucket-configuration LocationConstraint=$BUCKET_REGION
        fi
        echo "✅ S3 bucket created: $DOMAIN"
    fi
    
    # Configure bucket for website hosting
    aws s3 website s3://$DOMAIN --index-document index.html --error-document error.html
    
    # Attempt to set bucket policy for public read
    POLICY='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "PublicReadGetObject",
                "Effect": "Allow",
                "Principal": "*",
                "Action": "s3:GetObject",
                "Resource": "arn:aws:s3:::'$DOMAIN'/*"
            }
        ]
    }'
    
    echo "$POLICY" > /tmp/bucket_policy.json
    
    # Try to set the public policy, but handle failure due to Block Public Access
    if ! aws s3api put-bucket-policy --bucket $DOMAIN --policy file:///tmp/bucket_policy.json 2>/tmp/policy_error; then
        ERROR=$(cat /tmp/policy_error)
        if [[ $ERROR == *"BlockPublicPolicy"* || $ERROR == *"BlockPublicAccess"* ]]; then
            echo "⚠️ Unable to set public bucket policy due to S3 Block Public Access settings"
            echo "ℹ️ We'll configure CloudFront to use Origin Access Identity instead"
            
            # Create Origin Access Identity for CloudFront
            echo "🔑 Creating CloudFront Origin Access Identity..."
            OAI_CONFIG='{
                "CallerReference": "quickpage-oai-'$DOMAIN'-'$(date +%s)'",
                "Comment": "OAI for '$DOMAIN'"
            }'
            echo "$OAI_CONFIG" > /tmp/oai_config.json
            
            OAI_RESULT=$(aws cloudfront create-cloud-front-origin-access-identity --cloud-front-origin-access-identity-config file:///tmp/oai_config.json)
            OAI_ID=$(echo "$OAI_RESULT" | jq -r '.CloudFrontOriginAccessIdentity.Id')
            OAI_S3_CANONICAL_USER_ID=$(echo "$OAI_RESULT" | jq -r '.CloudFrontOriginAccessIdentity.S3CanonicalUserId')
            
            echo "✅ Created OAI: $OAI_ID"
            
            # Set bucket policy for CloudFront OAI
            OAI_POLICY='{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Sid": "CloudFrontReadGetObject",
                        "Effect": "Allow",
                        "Principal": {"CanonicalUser": "'$OAI_S3_CANONICAL_USER_ID'"},
                        "Action": "s3:GetObject",
                        "Resource": "arn:aws:s3:::'$DOMAIN'/*"
                    }
                ]
            }'
            
            echo "$OAI_POLICY" > /tmp/oai_policy.json
            aws s3api put-bucket-policy --bucket $DOMAIN --policy file:///tmp/oai_policy.json
            echo "✅ Bucket policy set for CloudFront access only (private bucket)"
            
            # Save OAI ID for CloudFront configuration
            USE_OAI=true
        else
            echo "❌ Error setting bucket policy: $ERROR"
        fi
    else
        echo "✅ Bucket configured for website hosting with public read access"
        USE_OAI=false
    fi
else
    echo "🔄 Skipping S3 bucket creation"
fi

# Step 3: Upload website files
if [[ $SKIP_UPLOAD == false ]]; then
    echo ""
    echo "📤 Step 3/4: Uploading website files..."
    
    if [[ ! -d $WEBSITE_DIR ]]; then
        echo "⚠️ Website directory not found: $WEBSITE_DIR"
        mkdir -p $WEBSITE_DIR
        echo "<html><body><h1>$DOMAIN</h1><p>Placeholder page created by QuickPage script</p></body></html>" > $WEBSITE_DIR/index.html
        echo "<html><body><h1>Error - Page Not Found</h1><p>Default error page created by QuickPage script</p></body></html>" > $WEBSITE_DIR/error.html
        echo "🔄 Created basic placeholder files in $WEBSITE_DIR"
    fi
    
    aws s3 sync $WEBSITE_DIR s3://$DOMAIN
    echo "✅ Website files uploaded to S3"
else
    echo "🔄 Skipping website file upload"
fi

    # Check if we need to validate the certificate
    CERT_STATUS=""
    if [[ -n $CERT_ARN ]]; then
        CERT_STATUS=$(aws acm describe-certificate --certificate-arn "$CERT_ARN" \
            --region $REGION --query "Certificate.Status" --output text)
        
        if [[ $CERT_STATUS != "ISSUED" && $SKIP_CUSTOM_DOMAIN != true ]]; then
            echo "⚠️ Certificate is not fully validated yet (Status: $CERT_STATUS)"
            echo "ℹ️ CloudFront requires validated certificates for custom domains"
            echo "Options:"
            echo "  1. Wait for certificate validation to complete"
            echo "  2. Run with --skip-custom-domain to create CloudFront without custom domain"
            echo "  3. Skip CloudFront creation for now with --skip-cloudfront"
            
            read -p "Would you like to continue without custom domain? (y/n): " CONTINUE_RESPONSE
            if [[ "${CONTINUE_RESPONSE,,}" == "y" ]]; then
                SKIP_CUSTOM_DOMAIN=true
                echo "✅ Continuing with CloudFront creation without custom domain"
            else
                echo "❌ Aborting CloudFront creation. Run again with one of the options above when ready."
                SKIP_CLOUDFRONT=true
            fi
        fi
    fi
    
    # Create CloudFront Distribution
    if [[ $SKIP_CLOUDFRONT == false ]]; then
        echo ""
        echo "☁️ Step 4/4: Creating CloudFront Distribution..."
        
        # Generate a unique caller reference
        CALLER_REF="quickpage-$DOMAIN-$(date +%s)"
        
        # Prepare Origin configuration based on whether we're using OAI or not
        if [[ $USE_OAI == true ]]; then
            # Create Origin configuration using OAI
            ORIGIN_CONFIG='{
                "Id": "S3Origin",
                "DomainName": "'$DOMAIN'.s3.'$BUCKET_REGION'.amazonaws.com",
                "S3OriginConfig": {
                    "OriginAccessIdentity": "origin-access-identity/cloudfront/'$OAI_ID'"
                }
            }'
        else
            # Create Origin configuration for website endpoint
            ORIGIN_CONFIG='{
                "Id": "S3Origin",
                "DomainName": "'$DOMAIN'.s3-website.'$BUCKET_REGION'.amazonaws.com",
                "CustomOriginConfig": {
                    "HTTPPort": 80,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "http-only",
                    "OriginSslProtocols": {
                        "Quantity": 1,
                        "Items": ["TLSv1.2"]
                    },
                    "OriginReadTimeout": 30,
                    "OriginKeepaliveTimeout": 5
                }
            }'
        fi
        
        # Create distribution configuration
        if [[ $SKIP_CUSTOM_DOMAIN == true ]]; then
            # Create CloudFront without custom domain
            cat > /tmp/cf-config.json << EOF
{
    "CallerReference": "$CALLER_REF",
    "Aliases": {
        "Quantity": 0
    },
    "DefaultRootObject": "index.html",
    "Origins": {
        "Quantity": 1,
        "Items": [$ORIGIN_CONFIG]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3Origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 2,
            "Items": ["GET", "HEAD"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {
                "Forward": "none"
            },
            "Headers": {
                "Quantity": 0
            }
        },
        "MinTTL": 0,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000,
        "Compress": true
    },
    "CustomErrorResponses": {
        "Quantity": 1,
        "Items": [
            {
                "ErrorCode": 404,
                "ResponsePagePath": "/error.html",
                "ResponseCode": "404",
                "ErrorCachingMinTTL": 300
            }
        ]
    },
    "Comment": "CloudFront distribution for $DOMAIN (without custom domain)",
    "Enabled": true,
    "PriceClass": "PriceClass_100",
    "ViewerCertificate": {
        "CloudFrontDefaultCertificate": true
    },
    "HttpVersion": "http2",
    "IsIPV6Enabled": true
}
EOF
        else
            # Create CloudFront with custom domain
            cat > /tmp/cf-config.json << EOF
{
    "CallerReference": "$CALLER_REF",
    "Aliases": {
        "Quantity": 1,
        "Items": ["$DOMAIN"]
    },
    "DefaultRootObject": "index.html",
    "Origins": {
        "Quantity": 1,
        "Items": [$ORIGIN_CONFIG]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3Origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 2,
            "Items": ["GET", "HEAD"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {
                "Forward": "none"
            },
            "Headers": {
                "Quantity": 0
            }
        },
        "MinTTL": 0,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000,
        "Compress": true
    },
    "CustomErrorResponses": {
        "Quantity": 1,
        "Items": [
            {
                "ErrorCode": 404,
                "ResponsePagePath": "/error.html",
                "ResponseCode": "404",
                "ErrorCachingMinTTL": 300
            }
        ]
    },
    "Comment": "CloudFront distribution for $DOMAIN",
    "Enabled": true,
    "PriceClass": "PriceClass_100",
    "ViewerCertificate": {
        "ACMCertificateArn": "$CERT_ARN",
        "SSLSupportMethod": "sni-only",
        "MinimumProtocolVersion": "TLSv1.2_2021"
    },
    "HttpVersion": "http2",
    "IsIPV6Enabled": true
}
EOF
        fi
    
    # Create the distribution
    DISTRIBUTION_INFO=$(aws cloudfront create-distribution --distribution-config file:///tmp/cf-config.json)
    DISTRIBUTION_ID=$(echo $DISTRIBUTION_INFO | jq -r '.Distribution.Id')
    DISTRIBUTION_DOMAIN=$(echo $DISTRIBUTION_INFO | jq -r '.Distribution.DomainName')
    
    echo "✅ CloudFront distribution created!"
    echo "⚙️ Distribution ID: $DISTRIBUTION_ID"
    echo "🌐 Distribution Domain: $DISTRIBUTION_DOMAIN"
    echo ""
    echo "🔷 FINAL DNS SETUP 🔷"
    echo "Create a new DNS record at your DNS provider:"
    echo "Type: CNAME"
    echo "Name: $DOMAIN (or @ for root domain)"
    echo "Value: $DISTRIBUTION_DOMAIN"
else
    echo "🔄 Skipping CloudFront distribution creation"
fi

echo ""
echo "========================================================"
echo "🎉 DEPLOYMENT COMPLETE!"
echo "========================================================"
if [[ $SKIP_CLOUDFRONT == false ]]; then
    echo "Your website will be available at https://$DOMAIN"
    echo "once you set up the final DNS record and the CloudFront distribution is deployed"
    echo "(which usually takes 10-30 minutes)."
    echo ""
    echo "To check status: aws cloudfront get-distribution --id $DISTRIBUTION_ID"
fi
echo "Website URL: http://$DOMAIN.s3-website.$BUCKET_REGION.amazonaws.com"
echo "S3 bucket:   s3://$DOMAIN"
if [[ -n $CERT_ARN ]]; then
    echo "Certificate: $CERT_ARN"
    echo "Certificate Status: $CERT_STATUS"
    
    if [[ $CERT_STATUS != "ISSUED" ]]; then
        echo ""
        echo "⚠️ Important: Your certificate is not yet validated. Once validated, you can:"
        echo "   1. Add your custom domain to the CloudFront distribution using:"
        echo "      aws cloudfront update-distribution --id $DISTRIBUTION_ID"
        echo "   2. Or run this script again with --skip-cert --cert-arn $CERT_ARN"
    fi
fi
echo "========================================================"
    echo "  --skip-cert-validation  Skip waiting for certificate validation"
    echo "  --cert-arn ARN          Use existing certificate ARN" 
    echo "  --skip-s3               Skip S3 bucket creation"
    echo "  --skip-upload           Skip uploading files to S3"
    echo "  --skip-cloudfront       Skip CloudFront distribution creation"
    echo "  --region REGION         Region for ACM and CloudFront (default: us-east-1)"
    echo "  --bucket-region REGION  Region for S3 bucket (default: eu-central-1)"
    echo "  --help                  Show this help message"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --website-dir)
            WEBSITE_DIR="$2"
            shift 2
            ;;
        --skip-cert)
            SKIP_CERT=true
            shift
            ;;
        --skip-cert-validation)
            SKIP_CERT_VALIDATION=true
            shift
            ;;
        --cert-arn)
            CERT_ARN="$2"
            SKIP_CERT=true
            shift 2
            ;;
        --skip-s3)
            SKIP_S3=true
            shift
            ;;
        --skip-upload)
            SKIP_UPLOAD=true
            shift
            ;;
        --skip-cloudfront)
            SKIP_CLOUDFRONT=true
            shift
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --bucket-region)
            BUCKET_REGION="$2"
            shift 2
            ;;
        --help)
            show_usage
            ;;
        *)
            if [[ -z $DOMAIN ]]; then
                DOMAIN="$1"
                shift
            else
                echo "ERROR: Unknown option $1"
                show_usage
            fi
            ;;
    esac
done

# Check if domain is provided
if [[ -z $DOMAIN ]]; then
    echo "ERROR: Domain name is required"
    show_usage
fi

echo "========================================================"
echo "🌍 QuickPage: Deploying $DOMAIN"
echo "========================================================"

# Step 1: Create or use existing SSL Certificate
if [[ $SKIP_CERT == false ]]; then
    echo "🔒 Step 1/4: Checking for existing certificates for $DOMAIN..."
    
    # Check if there's an existing certificate for this domain
    EXISTING_CERT_ARN=$(aws acm list-certificates --region $REGION \
        --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn" \
        --output text)
    
    if [[ -n $EXISTING_CERT_ARN ]]; then
        # Check if the certificate is valid and issued
        CERT_STATUS=$(aws acm describe-certificate --certificate-arn "$EXISTING_CERT_ARN" \
            --region $REGION --query "Certificate.Status" --output text)
        
        if [[ $CERT_STATUS == "ISSUED" ]]; then
            echo "✅ Found existing valid certificate for $DOMAIN"
            echo "Certificate ARN: $EXISTING_CERT_ARN"
            CERT_ARN=$EXISTING_CERT_ARN
        elif [[ $CERT_STATUS == "PENDING_VALIDATION" ]]; then
            echo "⏳ Found pending certificate for $DOMAIN that needs validation"
            echo "Certificate ARN: $EXISTING_CERT_ARN"
            CERT_ARN=$EXISTING_CERT_ARN
            
            # Get validation info for the pending certificate
            VALIDATION_INFO=$(aws acm describe-certificate \
                --certificate-arn "$CERT_ARN" \
                --region $REGION \
                --query "Certificate.DomainValidationOptions[0].ResourceRecord")
            
            VALIDATION_NAME=$(echo $VALIDATION_INFO | jq -r '.Name')
            VALIDATION_VALUE=$(echo $VALIDATION_INFO | jq -r '.Value')
            
            echo "📝 DNS Validation Required - Create this CNAME record:"
            echo "Name:  $VALIDATION_NAME"
            echo "Value: $VALIDATION_VALUE"
            echo ""
            echo "⚠️  ADD THIS TO YOUR DNS PROVIDER BEFORE CONTINUING"
            echo ""
            
            if [[ $SKIP_CERT_VALIDATION == true ]]; then
                echo "⚠️ Skipping validation wait as requested. CloudFront distribution will be created but won't work until certificate is validated."
                echo "ℹ️ You can check certificate status later with: aws acm describe-certificate --certificate-arn $CERT_ARN --region $REGION --query Certificate.Status"
            else
                read -p "Press Enter once you've added the CNAME record (or type 'skip' to proceed without waiting for validation)... " RESPONSE
                
                if [[ "${RESPONSE,,}" == "skip" ]]; then
                    echo "⚠️ Skipping validation wait. CloudFront distribution will be created but won't work until certificate is validated."
                    echo "ℹ️ You can check certificate status later with: aws acm describe-certificate --certificate-arn $CERT_ARN --region $REGION --query Certificate.Status"
                else
                    echo "⏳ Waiting for certificate validation (this may take several minutes)..."
                    aws acm wait certificate-validated --certificate-arn "$CERT_ARN" --region $REGION
                    echo "✅ Certificate validated successfully!"
                fi
            fi
        else
            echo "⚠️ Found existing certificate for $DOMAIN but status is: $CERT_STATUS"
            echo "Creating a new certificate instead..."
            EXISTING_CERT_ARN=""
        fi
    fi
    
    if [[ -z $EXISTING_CERT_ARN ]]; then
        echo "🔒 Creating new SSL Certificate in ACM..."
        CERT_ARN=$(aws acm request-certificate \
            --domain-name $DOMAIN \
            --validation-method DNS \
            --region $REGION \
            --query CertificateArn --output text)
        
        echo "✅ Certificate requested: $CERT_ARN"
        echo ""
        echo "📝 DNS Validation Required - Create this CNAME record:"
        
        # Wait briefly for the certificate to be created and validation info available
        sleep 5
        
        VALIDATION_INFO=$(aws acm describe-certificate \
            --certificate-arn "$CERT_ARN" \
            --region $REGION \
            --query "Certificate.DomainValidationOptions[0].ResourceRecord")
        
        VALIDATION_NAME=$(echo $VALIDATION_INFO | jq -r '.Name')
        VALIDATION_VALUE=$(echo $VALIDATION_INFO | jq -r '.Value')
        
        echo "Name:  $VALIDATION_NAME"
        echo "Value: $VALIDATION_VALUE"
        echo ""
        echo "⚠️  ADD THIS TO YOUR DNS PROVIDER BEFORE CONTINUING"
        echo ""
        
        read -p "Press Enter once you've added the CNAME record... " 
        
        echo "⏳ Waiting for certificate validation (this may take several minutes)..."
        aws acm wait certificate-validated --certificate-arn "$CERT_ARN" --region $REGION
        echo "✅ Certificate validated successfully!"
    fi
elif [[ -z $CERT_ARN ]]; then
    echo "❓ No certificate ARN provided. Checking for existing certificates..."
    
    # Check if there's an existing certificate for this domain
    EXISTING_CERT_ARN=$(aws acm list-certificates --region $REGION \
        --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn" \
        --output text)
    
    if [[ -n $EXISTING_CERT_ARN ]]; then
        # Check if the certificate is valid and issued
        CERT_STATUS=$(aws acm describe-certificate --certificate-arn "$EXISTING_CERT_ARN" \
            --region $REGION --query "Certificate.Status" --output text)
        
        if [[ $CERT_STATUS == "ISSUED" ]]; then
            echo "✅ Found existing valid certificate for $DOMAIN"
            echo "Certificate ARN: $EXISTING_CERT_ARN"
            CERT_ARN=$EXISTING_CERT_ARN
        elif [[ $CERT_STATUS == "PENDING_VALIDATION" ]]; then
            echo "⏳ Found pending certificate for $DOMAIN that needs validation"
            echo "Certificate ARN: $EXISTING_CERT_ARN"
            CERT_ARN=$EXISTING_CERT_ARN
            
            # Get validation info for the pending certificate
            VALIDATION_INFO=$(aws acm describe-certificate \
                --certificate-arn "$CERT_ARN" \
                --region $REGION \
                --query "Certificate.DomainValidationOptions[0].ResourceRecord")
            
            VALIDATION_NAME=$(echo $VALIDATION_INFO | jq -r '.Name')
            VALIDATION_VALUE=$(echo $VALIDATION_INFO | jq -r '.Value')
            
            echo "📝 DNS Validation Required - Create this CNAME record:"
            echo "Name:  $VALIDATION_NAME"
            echo "Value: $VALIDATION_VALUE"
            echo ""
            echo "⚠️  ADD THIS TO YOUR DNS PROVIDER BEFORE CONTINUING"
            echo ""
            
            read -p "Press Enter once you've added the CNAME record (or type 'skip' to proceed without waiting for validation)... " RESPONSE
            
            if [[ "${RESPONSE,,}" == "skip" ]]; then
                echo "⚠️ Skipping validation wait. CloudFront distribution will be created but won't work until certificate is validated."
                echo "ℹ️ You can check certificate status later with: aws acm describe-certificate --certificate-arn $CERT_ARN --region $REGION --query Certificate.Status"
            else
                echo "⏳ Waiting for certificate validation (this may take several minutes)..."
                aws acm wait certificate-validated --certificate-arn "$CERT_ARN" --region $REGION
                echo "✅ Certificate validated successfully!"
            fi
        else
            echo "⚠️ Found existing certificate for $DOMAIN but status is: $CERT_STATUS"
            echo "Please provide a valid certificate with --cert-arn or remove --skip-cert"
            exit 1
        fi
    else
        echo "❓ No existing certificates found for $DOMAIN"
        echo "Please provide a certificate ARN with --cert-arn or remove --skip-cert"
        exit 1
    fi
else
    echo "🔄 Using provided certificate: $CERT_ARN"
fi

# Step 2: Create S3 Bucket
if [[ $SKIP_S3 == false ]]; then
    echo ""
    echo "🪣 Step 2/4: Creating S3 Bucket..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket $DOMAIN 2>/dev/null; then
        echo "⚠️ Bucket already exists, skipping creation"
    else
        if [[ $BUCKET_REGION == "us-east-1" ]]; then
            aws s3api create-bucket \
                --bucket $DOMAIN \
                --region $BUCKET_REGION
        else
            aws s3api create-bucket \
                --bucket $DOMAIN \
                --region $BUCKET_REGION \
                --create-bucket-configuration LocationConstraint=$BUCKET_REGION
        fi
        echo "✅ S3 bucket created: $DOMAIN"
    fi
    
    # Configure bucket for website hosting
    aws s3 website s3://$DOMAIN --index-document index.html --error-document error.html
    
    # Attempt to set bucket policy for public read
    POLICY='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "PublicReadGetObject",
                "Effect": "Allow",
                "Principal": "*",
                "Action": "s3:GetObject",
                "Resource": "arn:aws:s3:::'$DOMAIN'/*"
            }
        ]
    }'
    
    echo "$POLICY" > /tmp/bucket_policy.json
    
    # Try to set the public policy, but handle failure due to Block Public Access
    if ! aws s3api put-bucket-policy --bucket $DOMAIN --policy file:///tmp/bucket_policy.json 2>/tmp/policy_error; then
        ERROR=$(cat /tmp/policy_error)
        if [[ $ERROR == *"BlockPublicPolicy"* || $ERROR == *"BlockPublicAccess"* ]]; then
            echo "⚠️ Unable to set public bucket policy due to S3 Block Public Access settings"
            echo "ℹ️ We'll configure CloudFront to use Origin Access Identity instead"
            
            # Create Origin Access Identity for CloudFront
            echo "🔑 Creating CloudFront Origin Access Identity..."
            OAI_CONFIG='{
                "CallerReference": "quickpage-oai-'$DOMAIN'-'$(date +%s)'",
                "Comment": "OAI for '$DOMAIN'"
            }'
            echo "$OAI_CONFIG" > /tmp/oai_config.json
            
            OAI_RESULT=$(aws cloudfront create-cloud-front-origin-access-identity --cloud-front-origin-access-identity-config file:///tmp/oai_config.json)
            OAI_ID=$(echo "$OAI_RESULT" | jq -r '.CloudFrontOriginAccessIdentity.Id')
            OAI_S3_CANONICAL_USER_ID=$(echo "$OAI_RESULT" | jq -r '.CloudFrontOriginAccessIdentity.S3CanonicalUserId')
            
            echo "✅ Created OAI: $OAI_ID"
            
            # Set bucket policy for CloudFront OAI
            OAI_POLICY='{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Sid": "CloudFrontReadGetObject",
                        "Effect": "Allow",
                        "Principal": {"CanonicalUser": "'$OAI_S3_CANONICAL_USER_ID'"},
                        "Action": "s3:GetObject",
                        "Resource": "arn:aws:s3:::'$DOMAIN'/*"
                    }
                ]
            }'
            
            echo "$OAI_POLICY" > /tmp/oai_policy.json
            aws s3api put-bucket-policy --bucket $DOMAIN --policy file:///tmp/oai_policy.json
            echo "✅ Bucket policy set for CloudFront access only (private bucket)"
            
            # Save OAI ID for CloudFront configuration
            USE_OAI=true
        else
            echo "❌ Error setting bucket policy: $ERROR"
        fi
    else
        echo "✅ Bucket configured for website hosting with public read access"
        USE_OAI=false
    fi
else
    echo "🔄 Skipping S3 bucket creation"
fi

# Step 3: Upload website files
if [[ $SKIP_UPLOAD == false ]]; then
    echo ""
    echo "📤 Step 3/4: Uploading website files..."
    
    if [[ ! -d $WEBSITE_DIR ]]; then
        echo "⚠️ Website directory not found: $WEBSITE_DIR"
        mkdir -p $WEBSITE_DIR
        echo "<html><body><h1>$DOMAIN</h1><p>Placeholder page created by QuickPage script</p></body></html>" > $WEBSITE_DIR/index.html
        echo "<html><body><h1>Error - Page Not Found</h1><p>Default error page created by QuickPage script</p></body></html>" > $WEBSITE_DIR/error.html
        echo "🔄 Created basic placeholder files in $WEBSITE_DIR"
    fi
    
    aws s3 sync $WEBSITE_DIR s3://$DOMAIN
    echo "✅ Website files uploaded to S3"
else
    echo "🔄 Skipping website file upload"
fi

# Step 4: Create CloudFront Distribution
if [[ $SKIP_CLOUDFRONT == false ]]; then
    echo ""
    echo "☁️ Step 4/4: Creating CloudFront Distribution..."
    
    # Generate a unique caller reference
    CALLER_REF="quickpage-$DOMAIN-$(date +%s)"
    
    # Prepare Origin configuration based on whether we're using OAI or not
    if [[ $USE_OAI == true ]]; then
        # Create Origin configuration using OAI
        ORIGIN_CONFIG='{
            "Id": "S3Origin",
            "DomainName": "'$DOMAIN'.s3.'$BUCKET_REGION'.amazonaws.com",
            "S3OriginConfig": {
                "OriginAccessIdentity": "origin-access-identity/cloudfront/'$OAI_ID'"
            }
        }'
    else
        # Create Origin configuration for website endpoint
        ORIGIN_CONFIG='{
            "Id": "S3Origin",
            "DomainName": "'$DOMAIN'.s3-website.'$BUCKET_REGION'.amazonaws.com",
            "CustomOriginConfig": {
                "HTTPPort": 80,
                "HTTPSPort": 443,
                "OriginProtocolPolicy": "http-only",
                "OriginSslProtocols": {
                    "Quantity": 1,
                    "Items": ["TLSv1.2"]
                },
                "OriginReadTimeout": 30,
                "OriginKeepaliveTimeout": 5
            }
        }'
    fi
    
    # Create distribution configuration
    cat > /tmp/cf-config.json << EOF
{
    "CallerReference": "$CALLER_REF",
    "Aliases": {
        "Quantity": 1,
        "Items": ["$DOMAIN"]
    },
    "DefaultRootObject": "index.html",
    "Origins": {
        "Quantity": 1,
        "Items": [$ORIGIN_CONFIG]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3Origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 2,
            "Items": ["GET", "HEAD"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {
                "Forward": "none"
            },
            "Headers": {
                "Quantity": 0
            }
        },
        "MinTTL": 0,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000,
        "Compress": true
    },
    "CustomErrorResponses": {
        "Quantity": 1,
        "Items": [
            {
                "ErrorCode": 404,
                "ResponsePagePath": "/error.html",
                "ResponseCode": "404",
                "ErrorCachingMinTTL": 300
            }
        ]
    },
    "Comment": "CloudFront distribution for $DOMAIN",
    "Enabled": true,
    "PriceClass": "PriceClass_100",
    "ViewerCertificate": {
        "ACMCertificateArn": "$CERT_ARN",
        "SSLSupportMethod": "sni-only",
        "MinimumProtocolVersion": "TLSv1.2_2021"
    },
    "HttpVersion": "http2",
    "IsIPV6Enabled": true
}
EOF
    
    # Create the distribution
    DISTRIBUTION_INFO=$(aws cloudfront create-distribution --distribution-config file:///tmp/cf-config.json)
    DISTRIBUTION_ID=$(echo $DISTRIBUTION_INFO | jq -r '.Distribution.Id')
    DISTRIBUTION_DOMAIN=$(echo $DISTRIBUTION_INFO | jq -r '.Distribution.DomainName')
    
    echo "✅ CloudFront distribution created!"
    echo "⚙️ Distribution ID: $DISTRIBUTION_ID"
    echo "🌐 Distribution Domain: $DISTRIBUTION_DOMAIN"
    echo ""
    echo "🔷 FINAL DNS SETUP 🔷"
    echo "Create a new DNS record at your DNS provider:"
    echo "Type: CNAME"
    echo "Name: $DOMAIN (or @ for root domain)"
    echo "Value: $DISTRIBUTION_DOMAIN"
else
    echo "🔄 Skipping CloudFront distribution creation"
fi

echo ""
echo "========================================================"
echo "🎉 DEPLOYMENT COMPLETE!"
echo "========================================================"
if [[ $SKIP_CLOUDFRONT == false ]]; then
    echo "Your website will be available at https://$DOMAIN"
    echo "once you set up the final DNS record and the CloudFront distribution is deployed"
    echo "(which usually takes 10-30 minutes)."
    echo ""
    echo "To check status: aws cloudfront get-distribution --id $DISTRIBUTION_ID"
fi
echo "Website URL: http://$DOMAIN.s3-website.$BUCKET_REGION.amazonaws.com"
echo "S3 bucket:   s3://$DOMAIN"
if [[ -n $CERT_ARN ]]; then
    echo "Certificate: $CERT_ARN"
fi
echo "========================================================"