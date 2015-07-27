require 'test_helper'

module MyLibGenericTests
  def setup
    @elsa   = Person.new('Elsa',   :female, 12, 30_123_123)
    @pepe   = Person.new('Pepe',   :male,   18, 30_123_121)
    @juan   = Person.new('Juan',   :male,   68, 1_321_120)
    @zulema = Person.new('Zulema', :female, 80, 4_123_121)

    @people = plp_class.new(@elsa, @pepe, @juan, @zulema)
  end

  
  def test_retired
    assert_equal [@juan, @zulema], @people.retired
  end

  def test_draftable
    assert plp_class.new(@pepe, @juan).draftable?
    refute @people.draftable?
  end

  def test_drafted
    assert_equal [@pepe], @people.drafted
  end
end
