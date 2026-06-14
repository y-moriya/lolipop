#!/bin/bash
ANMAN_TEST_MODE=true ruby scripts/clean_db.rb && ANMAN_TEST_MODE=true ruby scripts/test_api_security.rb
