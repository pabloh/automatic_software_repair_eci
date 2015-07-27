require 'minitest/autorun'
require 'minitest/reporters'
require 'test_mylib'

Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(color: true)]
