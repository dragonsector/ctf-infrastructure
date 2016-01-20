#!/usr/bin/env python

import os
import sys
import re
import glob
import hashlib
import requests.packages.urllib3

import jinja2
import markdown
import boto
from boto.s3.connection import S3Connection
from boto.route53.connection import Route53Connection
from boto.s3.key import Key
import boto.ec2

from sh import tar, rm, make, mkdir

requests.packages.urllib3.disable_warnings()

os.environ['S3_USE_SIGV4'] = 'True'

CATEGORIES = {
    're': "Reverse Engineering",
    'pwn': "Pwning",
    'crypto': "Cryptography",
    'steg': "Steganography",
    'web': "Web", # web is just fucking boring like that
    'net': "Network",
    'prog': "Programming",
    'hw': "Hardware",
    'misc': "Miscellaneous",
    'fore': "Forensics"
}

if len(sys.argv) < 2:
        print "Usage: {} task_number".format(sys.argv[0])
        sys.exit(1)

tn = sys.argv[1]

resources_dir = 'client-resources/{}'.format(tn)
meta_dir = 'meta/{}'.format(tn)

if not os.path.exists(resources_dir):
    make(resources_dir)

if not os.path.exists(meta_dir):
    make(meta_dir)


def fc(p):
    with open(p) as f:
        return f.read()

# class are for wusses
task = {}
for f in frozenset(['author', 'description', 'flag', 'name', 'type', 'color']):
    d = fc(os.path.join(meta_dir, f+'.txt'))
    task[f] = d.strip()
task['index'] = tn

categories = []
m = re.match(r'([a-z\/]+)([0-9]+)', task['type'])
for t in m.group(1).split('/'):
    categories.append(CATEGORIES[t])
category = ' / '.join(categories)
task['category'] = category
task['points'] = int(m.group(2))

print "-> {} ({})".format(task['name'], task['type'])

creds = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'creds')

s3 = boto.s3.connect_to_region('eu-central-1')
bucket_name = 'dragonsector-ctf-{}'.format(os.environ.get('DENV', 'test'))
print "-> Bucket", bucket_name
bucket = s3.get_bucket(bucket_name)
route53 = boto.route53.connect_to_region('eu-central-1')
hackable = route53.get_zone("hackable.software.")
change_set = boto.route53.record.ResourceRecordSets(route53, hackable.id)
ec2 =  boto.ec2.connect_to_region("eu-central-1")
reservations = ec2.get_all_reservations()

# get instances
# server_prefix = '{}-'.format(os.environ.get('DENV', 'test'))
server_addresses = {}
# cs = pyrax.cloudservers
# for server in cs.list():
#     if server.name.startswith(server_prefix):
#         name = server.name[len(server_prefix):]
#         server_addresses[name] = server.accessIPv4
for reservation in reservations:
    instance = reservation.instances[0]
    if 'Role' not in instance.tags:
        continue
    if instance.tags['Role'] == 'ctf-{}-task'.format(os.environ.get('DENV', 'test')):
        if instance.state != 'running':
            continue
        server_addresses[instance.tags['Task']] = instance.private_ip_address

# upload resource files
resource_paths = {}

# calculate hash from all files
h = hashlib.sha256()
for source_filename in glob.glob(resources_dir + '/*'):
    with open(source_filename) as f:
        d = f.read()
        h.update(d)
prefix = h.hexdigest()

if tn in server_addresses:
    address = server_addresses[tn]
    if os.environ.get('DENV', 'test') == 'test':
        u = change_set.add_change("UPSERT", '{}.test.hackable.software'.format(tn), 'A', ttl=60)
    else:
        u = change_set.add_change("UPSERT", '{}.hackable.software'.format(tn), 'A', ttl=60)
    u.add_value(address)
    change_set.commit()
else:
    print '-> OMG NO ADDRESS FOR {}'.format(tn)

for source_filename in glob.glob(resources_dir + '/*'):
    target_filename = source_filename.split('/')[-1]
    print "--> Resource: {}".format(target_filename)    

    target_path = '{}_{}/{}'.format(tn, prefix, target_filename)
    k = Key(bucket)
    k.name = target_path

    with open(source_filename) as f:
        k.set_contents_from_string(f.read())
    secure_https_url = 'https://{host}/{bucket}/{key}'.format(
        host=s3.server_name(),
        bucket=bucket_name,
        key=target_path)
    #resource_paths[target_filename] = container.cdn_uri + '/' + target_path
    resource_paths[target_filename] = secure_https_url

def _jinja_get_resource(r):
    return resource_paths[r]

def _jinja_get_address():
    if os.environ.get('DENV', 'test') == 'test':
        return '{}.test.hackable.software'.format(tn)
    else:
        return '{}.hackable.software'.format(tn)

e = jinja2.Environment()
description_template = e.from_string(task['description'])
description_rendered = description_template.render(resource=_jinja_get_resource,
                                                   address = _jinja_get_address)
task['description'] = markdown.markdown(description_rendered).replace("'", "\\'")
task['flag'] = hashlib.sha256(task['flag']).hexdigest()

challenge_template = e.from_string("""<?php
return new Challenge(
    {{task.points}}, #points
    '{{task.flag}}',
    '{{task.color}}', #color
    '{{task.name}} ({{task.category}}, {{task.points}})',
    '{{task.description|safe}}'
 );""")
challenge_rendered = challenge_template.render(task=task)

mkdir('-p', 'challenges')
class_path = 'challenges/task_{}.php'.format(task['index'].replace('-', ''))
with open(class_path, 'w') as f:
    f.write(challenge_rendered)

print '-> Generated ' + class_path
