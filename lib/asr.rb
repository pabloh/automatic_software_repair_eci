require 'unparser'
require 'minitest'
require 'diffy'

require 'pry'

module Minitest
  # Disable autorun from test files
  @@installed_at_exit = true
end

class SoftwareAutoRepair
  def initialize(code_path, suite_path)
    require code_path
    require suite_path

    @code, @suite = File.read(code_path), Minitest::Runnable.runnables.last
  end

  def try_to_fix
    return if failing_tests.none?

    each_variant do |variant|
      load_variant(variant)

      if run_failing_tests # Bug Oracle
        return print_fix(variant) if run_all_tests # Regression Oracle
      end
    end

    puts "No fixes found"
  end


  def run_test(test) # Returns true when test passes
    @suite.new(test).run.passed?
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

  def program_template
    @template ||= parse_program
  end

  def each_variant
    each_alternative_mapper do |mapper|
      yield AlternativeProgramsGenerator.new(mapper).process(program_template)
    end
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

  def parse_program
    detector = HotspotsDetector.new
    detector.process(as_ast(@code)).tap { @conflicts_graph = detector.detected_conflicts }
  end

  def each_alternative_mapper(&bl)
    mapper = {}.compare_by_identity
    enumerate_forests(@conflicts_graph, mapper, &bl)
  end

  def enumerate_forests(hotspots, mapper, &bl)
    first, *rest = hotspots

    first.conflicts.each_with_index do |hotspot, idx|
      mapper[hotspot] = idx
      rest.any? ? enumerate_hotspots(rest, mapper, &bl) : enumerate_conflicts(hotspots.conflicts, &bl)
    end
  end

  def enumerate_conflicts(hotspots, mapper, &bl)
    hotspots.each_with_index do |hotspot, idx|
      if hotspot.conflicts.none?
        bl.call(mapper)
      else
        enumerate_hotspots(hotspot.conflicts, mapper, &bl)
      end
    end
  end
end

class HotspotsDetector < Parser::AST::Processor
  def initialize
    @hotspots_stack = []
  end

  def detected_conflicts
    @hotspots_stack
  end

  def on_send(node)
    if hotspot_class = MessageHotspot.detect_hotspot_for(node)
      rec, sel, *args = *node
      new_rec, rec_hotspots = process_and_collect_hotspots(rec)
      new_args, args_hotspots = process_all_and_collect_hotspots(args)

      hotspot_at(hotspot_class, node, [new_rec, sel, *new_args], rec_hotspots + args_hotspots)
    else
      super
    end
  end

  def on_block(node)
    if hotspot_class = BlockHotspot.detect_hotspot_for(node)
      new_childs, hotspots = process_all_and_collect_hotspots(node.children)
      hotspot_at(hotspot_class, node, new_childs, hotspots)
    else
      super
    end
  end

private
  def hotspot_at(klass, node, new_childs, conflicts)
    new_node = node.updated(nil, new_childs)
    klass.new(new_node, conflicts: conflicts).tap {|h| @hotspots_stack.push(h) }
  end

  def process_all_and_collect_hotspots(nodes)
    nodes.each_with_object([[],[]]) do |node, (new_nodes, hotspots)|
      new_node, new_hotspots = process_and_collect_hotspots(node)

      new_nodes << new_node
      hotspots.concat(new_hotspots)
    end
  end

  def process_and_collect_hotspots(node)
    stack_size = @hotspots_stack.size
    new_node = process(node)
    hotspots = @hotspots_stack.pop(@hotspots_stack.size - stack_size)
    
    [new_node, hotspots]
  end
end


class AlternativeProgramsGenerator < Parser::AST::Processor
  def intialize(alternatives_mapper)
    @alternatives = alternatives_mapper
  end

  def on_hotspot(hotspot)
    alt_childs = process_all(hotspot.original_childs)
    alternative = hotspot.alternatives[index_for(hotspot)]
    alternative.updated(nil, alt_childs)
  end

private
  def index_for(hotspot)
    @iterator[hotspot]
  end
end


class Hotspot < Parser::AST::Node
  attr :conflicts
  
  class << self
    def inherited(subclass)
      (@subclasses ||= []) << subclass
    end

    def descendants
      @descendants ||= if @subclasses
                         @subclasses + @subclasses.flat_map(&:descendants)
                       else []
                       end
    end

    def detect_hotspot_for(node)
      descendants.detect {|subclass| subclass.applies?(node) }
    end

    def applies?(node)
      false
    end
  end

  def alternatives
    [original_node]
  end

  def original_node
    children.first
  end

  def original_childs
    original_node.to_a
  end

  def initialize(node, conflicts: [])
    @conflicts = conflicts
    super(:hotspot, [node])
  end
end

class MessageHotspot < Hotspot
  def self.selectors
    []
  end

  def self.applies?(node)
    _, selector = *node
    selectors.detect {|hotspot| hotspot === selector }
  end
end


class OperatorHotspot < MessageHotspot
  def alternatives
    self.class.selectors.map do |new_sel|
      rec, _sel, *args = *original_node
      original_node.updated(nil, [rec, new_sel, *args])
    end
  end
end

class ComparisonHotspot < OperatorHotspot
  def self.selectors
    [:>, :>=, :<, :<=]
  end
end

class EqualityHotspot < OperatorHotspot
  def self.selectors
    [:==, :!=]
  end
end

class PredicateHotspot < MessageHotspot
  def self.selectors
    [/\?\Z/]
  end

  def alternatives
    [original_node, Parser::AST::Node.new(:send, [original_node, :!])]
  end
end

class BlockHotspot < Hotspot
  def self.selectors
    []
  end

  def self.applies?(node)
    expression, _ = *node
    _, selector = *expression
    selectors.detect {|hotspot| hotspot === selector }
  end

  def alternatives
    exp, args, body = *original_node
    not_body = body ? Parser::AST::Node.new(:send, [body, :!]) : Parser::AST::Node.new(:true)

    [original_node, original_node.updated([exp, args, not_body])]
  end
end


class FilterHotspot < BlockHotspot
  def self.selectors
    [:select, :reject]
  end
end

class QuantifierHotspot < BlockHotspot
  def self.selectors
    [:all?, :none?, :any?, :one?]
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

ar = SoftwareAutoRepair.new(File.join(__dir__, 'asr/mylib_idiom.rb'), File.join(__dir__, '../test/test_mylib_idiom.rb'))
template = ar.program_template

puts template.inspect

#puts ProgramGenerator.new.process(metaprog)
