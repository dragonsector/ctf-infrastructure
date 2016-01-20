2015 Teaser Deployment
======================

The Milk Crate server provisioning system. Don't kick it too hard!

Backend in boto/ansible/ec2. Get yo API keys from q3k.

You'll need python, virtualenv, python-dev and build-essentials.

Usage
-----

Export some env vars to make stuff work:

    export AWS_ACCESS_KEY_ID=foobar
    export AWS_SECRET_ACCESS_KEY=foobarbaz
    export KEYPAIR=keypair-in-ec2

Then run `make help`, and you'll understand what you need.

Maintainer
----------

    Sergiusz Bazanski <q3k@q3k.org>
    Emergencies: +48 792973702
