require 'test_helper'
require 'asr/mylib_imp'

class TestMyLibImp < Minitest::Test
  include MyLibGenericTests

  def plp_class
    PeopleImp
  end
end
