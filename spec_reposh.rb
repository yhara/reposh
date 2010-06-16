#
# spec_reposh.rb - Unit test for Reposh
#
# you need RSpec and Kagemusha to run this.
#   gem install rspec
#   gem install kagemusha

require 'rubygems'
require 'kagemusha'
require './lib/reposh'

describe "Hash#recursive_merge" do
  before :all do
    @reposh = Reposh.new
  end

  it "should merge non-nested hash" do
    default = {:a => 1, :b => 2}
    config  = {:b => 3, :c => 4}

    merged = default.recursive_merge(config)
    merged.should == {:a => 1, :b => 3, :c => 4}
  end

  it "should merge nested hash" do
    default = {:a => {"foo" => 1}, :b => {"bar" => 2, "baz" => 3}}
    config = {:b => {"baz" => 4}}

    merged = default.recursive_merge(config)
    merged.should == {:a => {"foo" => 1}, 
                      :b => {"bar" => 2, "baz" => 4}}
  end

  it "should merge triple nested hash" do
    default = {:a => {"foo" => 1}, 
               :b => {:c => {"bar" => 2, "baz" => 3}}}
    config = {:b => {:c => {"baz" => 4}}}

    merged = default.recursive_merge(config)
    merged.should == {:a => {"foo" => 1}, 
                      :b => {:c => {"bar" => 2, "baz" => 4}}}
  end
end

describe "Reposh::Commands" do
  before :each do
    @commands = Reposh::Commands.new("svn", "status", [])
  end

  it "should judge whether a command matches a pattern" do
    @commands.match?("exit", "exit").should == true
    match = @commands.match?(/:(.*)/, ":rake aaa")
    match.should be_an_instance_of(MatchData)
    match[1].should == "rake aaa"
  end

  it "should register a command and dispatch" do
    @commands.register(/foo (.*) (\d+)/){|match|
      match[1].should == "bar"
      match[2].should == "1192"
    }
    @commands.dispatch("foo bar 1192", "svk")
  end

  it "should dispatch only for wanted systems" do
    @commands.register("foo"){ :no_match }
    @commands.register("foo", ["svn", "svk"]){ :match }

    @commands.dispatch("foo", "svn").should == :match
    @commands.dispatch("foo", "svk").should == :match
    @commands.dispatch("foo", "hg").should == :no_match
  end

  it "should register custom commands" do 
    my_execute = Kagemusha.new(Reposh::Commands).def(:execute){|x| x}

    @commands.register_custom_commands([
      { "pattern" => "ignore (\\S+)",
        "rule"    => "{system} propset svn:ignore . {$1}",
        "for"     => "svn, svk" }
    ])
    my_execute.swap{
      result = @commands.dispatch("ignore *.swp", "svn")
      result.should == "svn propset svn:ignore . *.swp"
    }
  end

  it "should add extname after executable name" do
    @commands.add_ext("rake stats", ".bat").should == "rake.bat stats"
  end

end
