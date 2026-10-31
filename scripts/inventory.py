#!/usr/bin/env python3
"""Read-only AWS inventory for before/after session comparisons, including untagged resources.

Never retrieves secret values, deletes resources or claims to be a billing audit.
All AWS operations are fixed in code; CLI input cannot select a write operation.
"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess

# Query only identifiers, status and ownership metadata; never secret payloads.
CHECKS = {
    'tagged_resources': ['resourcegroupstaggingapi', 'get-resources', '--query', 'ResourceTagMappingList[].{arn:ResourceARN,tags:Tags}'],
    'clusters': ['eks', 'list-clusters', '--query', 'clusters'],
    'instances': ['ec2', 'describe-instances', '--query', 'Reservations[].Instances[].{id:InstanceId,state:State.Name,type:InstanceType,vpc:VpcId,publicIp:PublicIpAddress,tags:Tags}'],
    'auto_scaling_groups': ['autoscaling', 'describe-auto-scaling-groups', '--query', 'AutoScalingGroups[].{name:AutoScalingGroupName,instances:Instances[].InstanceId,tags:Tags}'],
    'volumes': ['ec2', 'describe-volumes', '--query', 'Volumes[].{id:VolumeId,state:State,sizeGiB:Size,attachments:Attachments[].InstanceId,tags:Tags}'],
    'elastic_ips': ['ec2', 'describe-addresses', '--query', 'Addresses[].{id:AllocationId,ip:PublicIp,association:AssociationId,tags:Tags}'],
    'interfaces': ['ec2', 'describe-network-interfaces', '--query', 'NetworkInterfaces[].{id:NetworkInterfaceId,vpc:VpcId,description:Description,status:Status,publicIp:Association.PublicIp,tags:TagSet}'],
    'nat_gateways': ['ec2', 'describe-nat-gateways', '--query', 'NatGateways[].{id:NatGatewayId,vpc:VpcId,state:State,tags:Tags}'],
    'vpcs': ['ec2', 'describe-vpcs', '--query', 'Vpcs[].{id:VpcId,default:IsDefault,tags:Tags}'],
    'security_groups': ['ec2', 'describe-security-groups', '--query', 'SecurityGroups[].{id:GroupId,name:GroupName,vpc:VpcId,tags:Tags}'],
    'ebs_snapshots': ['ec2', 'describe-snapshots', '--owner-ids', 'self', '--query', 'Snapshots[].{id:SnapshotId,volume:VolumeId,sizeGiB:VolumeSize,state:State,tags:Tags}'],
    'load_balancers': ['elbv2', 'describe-load-balancers', '--query', 'LoadBalancers[].{arn:LoadBalancerArn,name:LoadBalancerName,vpc:VpcId,dns:DNSName,state:State.Code}'],
    'target_groups': ['elbv2', 'describe-target-groups', '--query', 'TargetGroups[].{arn:TargetGroupArn,name:TargetGroupName,vpc:VpcId,loadBalancers:LoadBalancerArns}'],
    'databases': ['rds', 'describe-db-instances', '--query', 'DBInstances[].{id:DBInstanceIdentifier,arn:DBInstanceArn,status:DBInstanceStatus,class:DBInstanceClass,tags:TagList}'],
    'database_snapshots': ['rds', 'describe-db-snapshots', '--snapshot-type', 'manual', '--query', 'DBSnapshots[].{id:DBSnapshotIdentifier,database:DBInstanceIdentifier,status:Status,tags:TagList}'],
    'retained_database_backups': ['rds', 'describe-db-instance-automated-backups', '--query', 'DBInstanceAutomatedBackups[].{id:DBInstanceIdentifier,status:Status,arn:DBInstanceAutomatedBackupsArn}'],
    'repositories': ['ecr', 'describe-repositories', '--query', 'repositories[].{arn:repositoryArn,name:repositoryName}'],
    'log_groups': ['logs', 'describe-log-groups', '--query', 'logGroups[].{name:logGroupName,bytes:storedBytes,retentionDays:retentionInDays}'],
    'alarms': ['cloudwatch', 'describe-alarms', '--alarm-types', 'MetricAlarm', 'CompositeAlarm', '--query', '{metric:MetricAlarms[].{arn:AlarmArn,name:AlarmName,state:StateValue},composite:CompositeAlarms[].{arn:AlarmArn,name:AlarmName,state:StateValue}}'],
    'certificates': ['acm', 'list-certificates', '--query', 'CertificateSummaryList[].{arn:CertificateArn,domain:DomainName,status:Status}'],
    'secret_metadata': ['secretsmanager', 'list-secrets', '--include-planned-deletion', '--query', 'SecretList[].{arn:ARN,name:Name,deletedDate:DeletedDate,tags:Tags}'],
    'queues': ['sqs', 'list-queues', '--query', 'QueueUrls'],
    'kms_keys': ['kms', 'list-keys', '--query', 'Keys[].{id:KeyId,arn:KeyArn}'],
    'topics': ['sns', 'list-topics', '--query', 'Topics[].TopicArn'],
    'buckets_global': ['s3api', 'list-buckets', '--query', 'Buckets[].{name:Name,created:CreationDate}'],
    'hosted_zones_global': ['route53', 'list-hosted-zones', '--query', 'HostedZones[].{id:Id,name:Name,private:Config.PrivateZone}'],
    'project_roles_global': ['iam', 'list-roles', '--query', 'Roles[?starts_with(RoleName, `commerce-aws-`)].{name:RoleName,arn:Arn,created:CreateDate}'],
    'project_policies_global': ['iam', 'list-policies', '--scope', 'Local', '--query', 'Policies[?starts_with(PolicyName, `commerce-aws-`)].{name:PolicyName,arn:Arn,attached:AttachmentCount,boundaries:PermissionsBoundaryUsageCount}'],
    'service_linked_roles_global': ['iam', 'list-roles', '--path-prefix', '/aws-service-role/', '--query', 'Roles[].{name:RoleName,arn:Arn,created:CreateDate}'],
}


def aws(profile, region, arguments):
    result = subprocess.run(['aws', '--profile', profile, '--region', region, '--no-cli-pager',
                             '--output', 'json', *arguments], capture_output=True, text=True, timeout=90)
    if result.returncode:
        # Do not print raw AWS errors or URLs; report the check and return code.
        raise RuntimeError(f'AWS CLI returned {result.returncode}; check permissions, session and connectivity')
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True)
    parser.add_argument('--account', required=True, help='Expected account ID; fails closed on a different identity')
    parser.add_argument('--region', choices=['ap-south-1'], default='ap-south-1')
    parser.add_argument('--output', type=Path, help='Defaults to an ignored timestamped .work/inventory report')
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9]{12}', args.account):
        parser.error('Expected a 12-digit AWS account ID')
    print('Verifying AWS account identity...', flush=True)
    identity = aws(args.profile, args.region, ['sts', 'get-caller-identity'])
    if identity['Account'] != args.account:
        raise SystemExit('Account mismatch: inventory stopped before resource queries')
    timestamp = dt.datetime.now(dt.timezone.utc)
    report = {'account': args.account, 'region': args.region, 'identity_arn': identity['Arn'],
              'time_utc': timestamp.isoformat(), 'resources': {}, 'errors': {}}
    for index, (name, operation) in enumerate(CHECKS.items(), 1):
        print(f'[{index}/{len(CHECKS)}] Checking {name}...', flush=True)
        try:
            result = aws(args.profile, args.region, operation)
            if name == 'kms_keys':
                result = [aws(args.profile, args.region, ['kms', 'describe-key', '--key-id', key['id'],
                          '--query', 'KeyMetadata.{id:KeyId,arn:Arn,state:KeyState,deletionDate:DeletionDate,manager:KeyManager,created:CreationDate}'])
                          for key in result]
            report['resources'][name] = result
        except (RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as failure:
            report['errors'][name] = type(failure).__name__
    report['complete'] = not report['errors']
    report['limitations'] = ['Mumbai inventory plus global bucket/hosted-zone names; other regions/services are not exhaustively covered.',
                             'A resource snapshot is not an AWS Billing audit. Review Billing separately.',
                             'Existing and untagged resources are intentionally included. Do not delete them automatically.']
    path = args.output or Path('.work/inventory') / (timestamp.strftime('%Y%m%dT%H%M%S%fZ') + '.json')
    os.umask(0o077)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Preserve the pre-session baseline; never silently overwrite it.
    with path.open('x') as output:
        json.dump(report, output, indent=2, default=str)
        output.write('\n')
    print('Saved inventory:', path)
    print('Checks completed:', len(report['resources']), 'Checks unavailable:', len(report['errors']))
    if report['errors']:
        print('Incomplete inventory checks:', ', '.join(report['errors']))
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
