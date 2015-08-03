### Prototype for an Automatic Software Repair Tool for Ruby

To run the demo ruby >= 2.1 is needed.
First, install the required gems with:

    bundle install

Then verify that tests are failing with

    rake test

To fix the programs, run

    bin/fix_ruby lib/asr/mylib_idiom.rb test/test_mylib_idiom.rb       # to patch the idiomatic version
    bin/fix_ruby lib/asr/mylib_imp.rb test/test_mylib_imp.rb           # to patch the iterative version
