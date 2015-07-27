Person = Struct.new(:name, :gender, :age, :dni) do
  def male?
    gender == :male
  end

  def female?
    gender == :female
  end

  def retired?
    age >= 65
  end
end

