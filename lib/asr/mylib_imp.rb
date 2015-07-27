require 'asr/person'

class PeopleImp
  def initialize(*list)
    @list = list
  end

  def drafted
    res = []
    @list.each do |person|
      if person.male?
        res << person unless person.dni % 2 == 0
      end
    end
    res
  end

  def retired
    res = []
    @list.each do |person|
      res << person if person.age <= 65
    end
    res
  end

  def draftable?
    @list.each do |person|
      return false if person.female?
    end
    return true
  end
end
