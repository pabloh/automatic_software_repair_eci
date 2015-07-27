require 'test_helper'
require 'asr/mylib_idiom'

class TestMyLibIdiom < Minitest::Test
  include MyLibGenericTests

  def plp_class
    PeopleIdiom
  end
end
