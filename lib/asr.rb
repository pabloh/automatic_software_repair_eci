require 'unparser'
require 'minitest'
require 'diffy'

require 'pry'

class SoftwareAutoRepair
  def initialize(code, suite)
    @code, @suite = code, suite
  end

  def try_to_fix
    return unless failing_tests.any?

    variants.each do |variant|
      load_variant(variant)

      if run_failing_tests # Bug Oracle
        return print_fix(variant) if run_all_tests # Regression Oracle
      end
    end

    puts "No fixes found"
  end


  def run_test(test) # Returns true when test passes
    @suite.new(test).run.failures.none?
  end

  def run_all_tests
    @suite.runnable_methods.all? {|test| run_test(test) }
  end

  def run_failing_tests
    failing_tests.all? {|test| run_test(test) }
  end

  def failing_tests
    @failing_tests ||= @suite.runnable_methods.reject {|test| run_test(test) }
  end

  def code_template
    HotspotsDetector.new.process(as_ast(@code))
  end

  def variants
    return [<<-EOF]
require 'asr/person'

class PeopleIdiom
  def initialize(*list)
    @list = list
  end

  def retired
    @list.select {|person| person.age >= 65 }
  end

  def drafted
    @list.select {|person| person.male? }.reject {|person| person.dni.even? }
  end

  def draftable?
    @list.all? {|person| !person.female? }
  end
end
    EOF

    template = code_template

    res, processor = [], ProgramGenerator.new
    while variant = processor.process(template)
      res << as_source(variant)
    end
    res
  end

private
  def print_fix(variant)
    puts "Generated fix for failing tests:\n"
    puts Diffy::Diff.new(@code, variant, context: 3, include_diff_info: true).to_s(:color).
      sub(%r{--- /tmp/diffy.[^\n]+}, '--- original file').
      sub(%r{\+\+\+ /tmp/diffy.[^\n]+}, '+++ fixed file')
  end

  def as_ast(code)
    Parser::CurrentRuby.parse(code)
  end

  def as_source(ast)
    Unparser.unparse(ast)
  end

  def load_variant(variant)
    old_verbose, $VERBOSE = $VERBOSE, nil
    TOPLEVEL_BINDING.eval(variant)
  ensure
    $VERBOSE = old_verbose
  end
end

class ProgramGenerator < Parser::AST::Processor
  def on_hotspot(node)
    alternatives = node.alternatives
    next_alternative = alternatives.first
  end
end

class HotspotsDetector < Parser::AST::Processor
  def on_send(node)
    if hotspot_class = OperatorHotspots.hotspot_type_for(node)
      hotspot_class.new(node)
    else
      super
    end
  end

  def on_block(node)
    selector, cond = node.children.first.children.last, node.children.last

    if HOTSPOTS.detect {|hotspot| hotspot === selector }
      children = process_all(node.children)
      children[-1] = Hotspot.new(cond)

      node.updated(nil, children, nil)
    else
      super
    end
  end
end

class Hotspot < Parser::AST::Node
  attr :original_node

  def self.applies?(node)
    fail 'must implement'
  end

  def alternatives
    fail 'must implement'
  end

  def initialize(node)
    type = :"#{self.class.name}_hotspot"
    super(type, [node])
  end
end

module Hotspots
  def self.hotspot_type_for(node)
    constants.find {|cls| cls.applies?(node) }
  end

  class Filter < Hotspot
    NAMES = [:select, :reject]

    def self.applies?(node)
      selector, cond = node.children.first.children.last, node.children.last
      NAMES.detect {|hotspot| hotspot == selector }
    end

    def alternatives
    end
  end

  class Quantifier < Hotspot
    NAMES = [:all?, :none?, :any?, :one?]

    def self.applies?(node)
      selector, cond = node.children.first.children.last, node.children.last
      NAMES.detect {|hotspot| hotspot == selector }
    end

    def alternatives
    end
  end

  class Predicate < Hotspot
    PATTERN = /\?\Z/

    def self.applies?(node)
      selector, cond = node.children.first.children.last, node.children.last
      PATERN =~ selector
    end

    def alternatives
      [original_node, Parser::AST::Node.new(:send, [original_node, :!])]
    end
  end

  class Comparison < Hotspot
    OPERATORS = [:>, :>=, :<, :<=]

    def self.applies?(node)
    end

    def alternatives
      oper = original_node.children[1]

      OPERATORS.map do |new_oper|
        new_childs = original_node.children.dup
        new_childs[1] = new_oper
        original_node.updated(nil, new_childs, nil)
      end
    end
  end

  class Equality < Hotspot
    OPERATORS = [:==, :!=]

    def self.applies?(node)
    end

    def alternatives
      oper = original_node.children[1]

      OPERATORS.map do |new_oper|
        new_childs = original_node.children.dup
        new_childs[1] = new_oper
        original_node.updated(nil, new_childs, nil)
      end
    end
  end
end

### Borrar luego todo esto
__END__

example1 = <<CODE
  arr = [23, 11, 12, 42, 12, 20]
  result = []
  for val in arr
    res << val if val < 20
  end

  res
CODE

example2 = <<CODE
  arr = [23, 11, 12, 42, 12]
  res = arr.select {|val| val < 20 }
CODE

example3 = <<CODE
  arr = [23, 11, 12, 42, 12]
  res = arr.select {|val| val.even? }
CODE

ar = SoftwareAutoRepair.new
metaprog = ar.template_for(example3)

puts ProgramGenerator.new.process(metaprog)
