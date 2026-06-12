#!/bin/bash
ruby scripts/clean_db.rb && ruby scripts/test_api_security.rb
