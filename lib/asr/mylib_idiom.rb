require 'asr/person'

# People class using idiomatic ruby source code
class PeopleIdiom
  def initialize(*list)
    @list = list
  end

  def retired
    @list.select {|person| person.age <= 65 }
  end

  def drafted
    @list.select {|person| person.male? }.select {|person| person.dni.even? }
  end

  def draftable?
    @list.any? {|person| !person.female? }
  end
end
