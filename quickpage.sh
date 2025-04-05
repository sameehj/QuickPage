#!/bin/bash

# quickpage.sh - Secure S3/CloudFront/ACM deployment script
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
DEBUG=false

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
    echo "  --debug                 Run debug script to analyze AWS resources"
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
        --debug)
            DEBUG=true
            shift
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

# Check dependencies
function check_dependencies {
    echo "🔍 Checking dependencies..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        echo "❌ AWS CLI is not installed. Please install it to use this script."
        exit 1
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        echo "❌ jq is not installed. Please install it to use this script."
        exit 1
    fi
    
    echo "✅ All dependencies are installed."
}

# Run debug script if --debug flag is provided
if [[ $DEBUG == true ]]; then
    if [[ -f ./scripts/debug_aws_resources.sh ]]; then
        ./scripts/debug_aws_resources.sh
    else
        echo "❌ Debug script not found at ./scripts/debug_aws_resources.sh"
    fi
    exit 0
fi

# Check if domain is provided
if [[ -z $DOMAIN ]]; then
    echo "ERROR: Domain name is required"
    show_usage
fi

# Check dependencies
check_dependencies

echo "========================================================"
echo "🌍 QuickPage: Deploying $DOMAIN"
echo "========================================================"

# Step 1: Create or use existing SSL Certificate
if [[ $SKIP_CERT == false ]]; then
    echo "🔒 Step 1/4: Checking for existing certificates for $DOMAIN..."
    
    # Check if there's an existing certificate for this domain
    EXISTING_CERT_ARN=$(aws acm list-certificates --region $REGION \
        --query "CertificateSummaryList[?DomainName=='$DOMAIN' || DomainName=='*.$DOMAIN'].CertificateArn" \
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
            --subject-alternative-names "*.$DOMAIN" \
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
        
        if [[ $SKIP_CERT_VALIDATION == true ]]; then
            echo "⚠️ Skipping validation wait as requested."
        else
            read -p "Press Enter once you've added the CNAME record (or type 'skip' to proceed without waiting for validation)... " RESPONSE
            
            if [[ "${RESPONSE,,}" == "skip" ]]; then
                echo "⚠️ Skipping validation wait. CloudFront distribution will be created but won't work until certificate is validated."
            else
                echo "⏳ Waiting for certificate validation (this may take several minutes)..."
                aws acm wait certificate-validated --certificate-arn "$CERT_ARN" --region $REGION
                echo "✅ Certificate validated successfully!"
            fi
        fi
    fi
elif [[ -z $CERT_ARN ]]; then
    echo "❓ No certificate ARN provided. Checking for existing certificates..."
    
    # Check if there's an existing certificate for this domain
    EXISTING_CERT_ARN=$(aws acm list-certificates --region $REGION \
        --query "CertificateSummaryList[?DomainName=='$DOMAIN' || DomainName=='*.$DOMAIN'].CertificateArn" \
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
                echo "⚠️ Skipping validation wait as requested."
            else
                read -p "Press Enter once you've added the CNAME record (or type 'skip' to proceed without waiting for validation)... " RESPONSE
                
                if [[ "${RESPONSE,,}" == "skip" ]]; then
                    echo "⚠️ Skipping validation wait. CloudFront distribution will be created but won't work until certificate is validated."
                else
                    echo "⏳ Waiting for certificate validation (this may take several minutes)..."
                    aws acm wait certificate-validated --certificate-arn "$CERT_ARN" --region $REGION
                    echo "✅ Certificate validated successfully!"
                fi
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
    
    # Block public access (recommended for security)
    aws s3api put-public-access-block \
        --bucket $DOMAIN \
        --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    echo "✅ Public access blocked for security"
    
    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket $DOMAIN \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    },
                    "BucketKeyEnabled": true
                }
            ]
        }'
    echo "✅ Default encryption enabled"
    
    # Configure bucket for website hosting
    aws s3 website s3://$DOMAIN --index-document index.html --error-document error.html
    echo "✅ Configured as a static website"
    
    # Set up CORS
    aws s3api put-bucket-cors \
        --bucket $DOMAIN \
        --cors-configuration '{
            "CORSRules": [
                {
                    "AllowedHeaders": ["Authorization", "Content-Length"],
                    "AllowedMethods": ["GET"],
                    "AllowedOrigins": ["https://'$DOMAIN'", "https://*.'$DOMAIN'"],
                    "ExposeHeaders": [],
                    "MaxAgeSeconds": 3000
                }
            ]
        }'
    echo "✅ CORS configuration set"
    
    # Create Origin Access Control for CloudFront
    echo "🔑 Creating CloudFront Origin Access Control..."
    OAC_NAME="OAC-$DOMAIN-$(date +%s)"
    
    # Check if OAC already exists
    EXISTING_OAC=$(aws cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?Name=='$OAC_NAME'].Id" --output text)
    
    if [[ -z $EXISTING_OAC ]]; then
        OAC_CONFIG='{
            "OriginAccessControlConfig": {
                "Name": "'$OAC_NAME'",
                "OriginAccessControlOriginType": "s3",
                "SigningBehavior": "always",
                "SigningProtocol": "sigv4"
            }
        }'
        
        echo "$OAC_CONFIG" > /tmp/oac_config.json
        
        OAC_RESULT=$(aws cloudfront create-origin-access-control --cli-input-json file:///tmp/oac_config.json)
        OAC_ID=$(echo "$OAC_RESULT" | jq -r '.OriginAccessControl.Id')
        
        echo "✅ Created OAC: $OAC_ID"
    else
        OAC_ID=$EXISTING_OAC
        echo "⚠️ Using existing OAC: $OAC_ID"
    fi
    
    # Set bucket policy for CloudFront OAC
    BUCKET_POLICY='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "AllowCloudFrontServicePrincipalReadOnly",
                "Effect": "Allow",
                "Principal": {
                    "Service": "cloudfront.amazonaws.com"
                },
                "Action": "s3:GetObject",
                "Resource": "arn:aws:s3:::'$DOMAIN'/*",
                "Condition": {
                    "StringEquals": {
                        "AWS:SourceArn": "arn:aws:cloudfront::'$(aws sts get-caller-identity --query Account --output text)':distribution/*"
                    }
                }
            }
        ]
    }'
    
    echo "$BUCKET_POLICY" > /tmp/bucket_policy.json
    aws s3api put-bucket-policy --bucket $DOMAIN --policy file:///tmp/bucket_policy.json
    echo "✅ Bucket policy set for CloudFront access only (private bucket)"
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
    
    # Set appropriate content types and caching headers
    echo "📝 Setting optimal file properties..."
    
    # Upload with proper content types and caching
    find $WEBSITE_DIR -type f -name "*.html" | while read file; do
        aws s3 cp "$file" "s3://$DOMAIN/${file#$WEBSITE_DIR/}" --content-type "text/html" --cache-control "max-age=3600"
    done
    
    find $WEBSITE_DIR -type f -name "*.css" | while read file; do
        aws s3 cp "$file" "s3://$DOMAIN/${file#$WEBSITE_DIR/}" --content-type "text/css" --cache-control "max-age=86400"
    done
    
    find $WEBSITE_DIR -type f -name "*.js" | while read file; do
        aws s3 cp "$file" "s3://$DOMAIN/${file#$WEBSITE_DIR/}" --content-type "application/javascript" --cache-control "max-age=86400"
    done
    
    find $WEBSITE_DIR -type f \( -name "*.jpg" -o -name "*.jpeg" \) | while read file; do
        aws s3 cp "$file" "s3://$DOMAIN/${file#$WEBSITE_DIR/}" --content-type "image/jpeg" --cache-control "max-age=2592000"
    done
    
    find $WEBSITE_DIR -type f -name "*.png" | while read file; do
        aws s3 cp "$file" "s3://$DOMAIN/${file#$WEBSITE_DIR/}" --content-type "image/png" --cache-control "max-age=2592000"
    done
    
    find $WEBSITE_DIR -type f -name "*.svg" | while read file; do
        aws s3 cp "$file" "s3://$DOMAIN/${file#$WEBSITE_DIR/}" --content-type "image/svg+xml" --cache-control "max-age=2592000"
    done
    
    # Upload any remaining files
    aws s3 sync $WEBSITE_DIR s3://$DOMAIN --exclude "*.*" --include "*"
    
    echo "✅ Website files uploaded to S3 with optimized settings"
else
    echo "🔄 Skipping website file upload"
fi

# Check certificate status before proceeding with CloudFront
if [[ -n $CERT_ARN && $SKIP_CLOUDFRONT == false ]]; then
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

# Step 4: Create CloudFront Distribution
if [[ $SKIP_CLOUDFRONT == false ]]; then
    echo ""
    echo "☁️ Step 4/4: Creating CloudFront Distribution..."
    
    # Generate a unique caller reference
    CALLER_REF="quickpage-$DOMAIN-$(date +%s)"
    
    # Security headers policy
    echo "🔒 Creating security headers policy..."
    POLICY_NAME="QuickPageSecurityPolicy-$DOMAIN"
    
    HEADERS_POLICY='{
        "SecurityHeadersConfig": {
            "XSSProtection": {
                "Override": true,
                "Protection": true,
                "ModeBlock": true
            },
            "StrictTransportSecurity": {
                "Override": true,
                "IncludeSubdomains": true,
                "Preload": true,
                "AccessControlMaxAgeSec": 63072000
            },
            "ContentTypeOptions": {
                "Override": true
            },
            "ReferrerPolicy": {
                "Override": true,
                "ReferrerPolicy": "strict-origin-when-cross-origin"
            },
            "ContentSecurityPolicy": {
                "Override": true,
                "ContentSecurityPolicy": "default-src ''self''; img-src ''self'' data:; script-src ''self''; style-src ''self'' ''unsafe-inline''; font-src ''self''; object-src ''none''; connect-src ''self''"
            },
            "FrameOptions": {
                "Override": true,
                "FrameOption": "DENY"
            }
        }
    }'
    
    # Check if policy already exists
    EXISTING_POLICY_ID=$(aws cloudfront list-response-headers-policies --query "ResponseHeadersPolicyList.Items[?Name=='$POLICY_NAME'].Id" --output text)
    
    if [[ -z $EXISTING_POLICY_ID ]]; then
        echo "$HEADERS_POLICY" > /tmp/headers_policy.json
        POLICY_CONFIG="{\"Name\": \"$POLICY_NAME\", $(cat /tmp/headers_policy.json)}"
        echo "$POLICY_CONFIG" > /tmp/policy_config.json
        
        POLICY_RESULT=$(aws cloudfront create-response-headers-policy --cli-input-json file:///tmp/policy_config.json)
        POLICY_ID=$(echo "$POLICY_RESULT" | jq -r '.ResponseHeadersPolicy.Id')
        
        echo "✅ Created security headers policy: $POLICY_ID"
    else
        POLICY_ID=$EXISTING_POLICY_ID
        echo "⚠️ Using existing security headers policy: $POLICY_ID"
    fi
    
    # Create Origin configuration using Origin Access Control
    ORIGIN_CONFIG='{
        "Id": "S3Origin",
        "DomainName": "'$DOMAIN'.s3.'$BUCKET_REGION'.amazonaws.com",
        "OriginAccessControlId": "'$OAC_ID'",
        "OriginPath": "",
        "ConnectionAttempts": 3,
        "ConnectionTimeout": 10,
        "CustomHeaders": {
            "Quantity": 0
        },
        "OriginShield": {
            "Enabled": false
        }
    }'
    
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
    "OriginGroups": {
        "Quantity": 0
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
        "ResponseHeadersPolicyId": "$POLICY_ID",
        "SmoothStreaming": false,
        "Compress": true,
        "LambdaFunctionAssociations": {
            "Quantity": 0
        },
        "FunctionAssociations": {
            "Quantity": 0
        },
        "FieldLevelEncryptionId": "",
        "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
        "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
    },
    "CacheBehaviors": {
        "Quantity": 0
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
    "Logging": {
        "Enabled": false,
        "IncludeCookies": false,
        "Bucket": "",
        "Prefix": ""
    },
    "PriceClass": "PriceClass_100",
    "Enabled": true,
    "ViewerCertificate": {
        "CloudFrontDefaultCertificate": true,
        "MinimumProtocolVersion": "TLSv1.2_2021"
    },
    "Restrictions": {
        "GeoRestriction": {
            "RestrictionType": "none",
            "Quantity": 0
        }
    },
    "WebACLId": "",
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
    "OriginGroups": {
        "Quantity": 0
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
        "ResponseHeadersPolicyId": "$POLICY_ID",
        "SmoothStreaming": false,
        "Compress": true,
        "LambdaFunctionAssociations": {
            "Quantity": 0
        },
        "FunctionAssociations": {
            "Quantity": 0
        },
        "FieldLevelEncryptionId": "",
        "CachePolicyId": "658327ea-f89d-4fab-a63d-7e