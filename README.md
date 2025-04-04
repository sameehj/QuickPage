Certainly! Here's the updated README for **QuickPage**:

---

# QuickPage 🚀

> The fastest, most cost-effective, and fully open-source solution to deploy static landing pages on AWS using S3, CloudFront, and ACM.

---

## Why QuickPage?

Are you frustrated with expensive or sluggish landing page hosting platforms?  
Do you desire full control over your infrastructure while ensuring high performance and minimal costs?

**QuickPage** offers a streamlined approach to deploy static sites leveraging:

- **AWS S3**:Reliable and scalable storage for your static assets
- **AWS CloudFront**:Global Content Delivery Network (CDN) for low-latency content delivery
- **AWS Certificate Manager (ACM)**:Automated provisioning of SSL/TLS certificates for secure HTTPS connections
- **AWS Route 53** (optional):Simplified custom domain setup and DNS management

With **QuickPage**, you avoid vendor lock-in and hidden fees.  
Experience **blazing speed**, **complete ownership**, and **AWS-native performance**.

---

## ✨ Features

- ✅ **Fully Open-Source**:Transparent and community-driven development
- ⚡️ **Optimized for Speed**:Utilizes AWS CloudFront for rapid content delivery
- 💸 **Cost-Effective** Benefit from AWS's pay-per-use pricing mode.
- 🔒 **Automatic SSL Certificates*: Seamless HTTPS integration via AWS Certificate Managr.
- 🌍 **Custom Domain Support*: Easily configure your own domain with AWS Route53.
- 💥 **One-Click Deploymen**: Deploy effortlessly using AWS Cloud Development Kit (DK).
- 🪄 **CI/CD Reay**: Integrates smoothly with GitHub Actions and other CI/CD pipeines.

---

## 🏃‍♂️ Quick Start

**Prerequisites**

- AWS CLI configured with appropriate credetial.
- Node.js version 16 or ighe.
- AWS CDK installed glbally:

  ```bash
  npm install -g aws-cdk
  ``

- An existing Route 53 hosted zone if you plan to use a custom omain.

**Deployment Steps:**

1. **Clone the Repository:**

   ```bash
   git clone https://github.com/your-repo/quickpage.git
   cd quickpage
   ```

2. **Install Dependencies:**

   ```bash
   npm install
   ```

3. **Configure AWS Resources:**

   - **S3 Bucet**: Stores your static websitefiles.
   - **CloudFront Distributon**: Delivers your content globally with low ltency.
   - **ACM Certificte**: Provides SSL/TLS for secure connetions.
   - **Route 53 Records** (optinal): Sets up DNS records for your custom omain.

   Ensure your AWS CLI is configured with the necessary permissions to create these resources.

4. **Deploy with CDK:**

   The deployment script automates the setup of the AWS resources mentioned above.

   ```bash
   cdk deploy
   ```

5. **Upload Your Static Site:**

   After deployment, sync your static site files to the created S3 bucket:

   ```bash
   aws s3 sync ./path-to-your-static-site s3://your-bucket-name
   ```

6. **Access Your Site:**

   Once the files are uploaded, your site will be accessible via the CloudFront distribution domain or your custom domain if configured.

---

## 🛠 Debugging AWS Resources

**QuickPage** includes a debugging script to help you inspect and troubleshoot the AWS resources it manages.

**Usge:**

To run the debugging script indepedently:

```bash
./scripts/debug_aws_resources.s
```


Alternatively, you can invoke it using the `--debug` flag with the main `quickpage.sh`script:

```bash
./quickpage.sh --debu
```


The debugging script provides detailed informatio abou:

- S3 Bucket configurations (ACLs, policies, locations, website seting).
- CloudFront distributions and their rigis.
- ACM certificates associated with your omains.

---

## 📚 Documentation

For comprehensive guides and advanced configurations, refer to our [official documentation](https://github.com/your-repo/quickpage/docs).

---

## 🤝 Contributing

We welcome contributions! Please read our [contributing guidelines](https://github.com/your-repo/quickpage/CONTRIBUTING.md) to get started.

---

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](https://github.com/your-repo/quickpage/LICENSE) file for detals.

---

*QuickPage is not affiliated with Amazon Web Services (AWS). AWS, S3, CloudFront, ACM, and Route 53 are trademarks of Amazon.com, Inc. or its afiliates.*

--- 