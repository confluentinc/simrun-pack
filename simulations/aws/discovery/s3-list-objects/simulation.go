package simulations

import (
	"context"
	_ "embed"

	"github.com/IBM/simrun/pack"
	packaws "github.com/IBM/simrun/pack/aws"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

//go:embed main.tf
var terraform string

func init() {
	pack.Register(pack.Simulation{
		ID:   "s3-list-objects",
		Name: "S3 Bucket Object Listing",
		Description: `Lists objects in an S3 bucket to simulate cloud storage discovery.

Warm-up:
- Create an S3 bucket

Detonation:
- Call s3:ListObjectsV2 on the bucket to enumerate its contents
- This generates S3 data events that can be detected

This technique tests detection of cloud storage object discovery activity.`,
		MITRE:     pack.MITREMapping{Tactics: []string{"TA0007"}, Techniques: []string{"T1619"}},
		Scope:     "aws",
		Terraform: terraform,
		Detonate:  Detonate,
	})
}

// Detonate lists objects in the S3 bucket.
func Detonate(ctx context.Context, input pack.DetonateInput) (*pack.Result, error) {
	log := pack.Logger(input)

	cfg, err := packaws.AWSConfig(ctx)
	if err != nil {
		return nil, err
	}

	bucketName := input.TerraformOutputs["bucket_name"]
	bucketRegion := input.TerraformOutputs["bucket_region"]

	// Pin the S3 client to the bucket's region. The bucket lives in whatever
	// region Terraform created it in, which may differ from the region the
	// default credential chain resolves. A mismatch yields a 301
	// PermanentRedirect from S3.
	s3Client := s3.NewFromConfig(cfg, func(o *s3.Options) {
		if bucketRegion != "" {
			o.Region = bucketRegion
		}
	})

	log.WithField("bucket_name", bucketName).Info("Listing objects in S3 bucket")

	output, err := s3Client.ListObjectsV2(ctx, &s3.ListObjectsV2Input{
		Bucket: aws.String(bucketName),
	})
	if err != nil {
		return pack.ErrorResult(pack.ErrCodeInternalError, "failed to list objects: "+err.Error()), nil
	}

	objectCount := int(aws.ToInt32(output.KeyCount))
	log.WithField("object_count", objectCount).Info("Successfully listed objects in S3 bucket")

	return pack.SuccessResult(map[string]any{
		"bucket_name":  bucketName,
		"object_count": objectCount,
	}), nil
}
