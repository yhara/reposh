require 'readline'
require 'yaml'
require 'optparse'
require 'pathname'

class Hash
  def recursive_merge(other)
    self.merge(other) do |key, my_val, other_val|
      # for values of a same key
      if my_val.is_a? Hash and other_val.is_a? Hash
        my_val.recursive_merge(other_val) # XXX: hang-ups for cyclic hash?
      else
        other_val
      end
    end
  end
end

class Reposh
  VERSION = File.read(Pathname(__FILE__).dirname + "../VERSION").chomp
  CONF_DEFAULT = { 
    "global" => {
      "editing_mode" => nil,
      "custom_commands" => [],
      "pathext" => [],
    },
    "system" => {
      "default" => {
        "binpath" => nil,
        "prompt" => "> ",
        "default_cmd" => "status",
      },
      "darcs" => {
        "default_cmd" => "whatsnew --summary",
      }
    }
  }

  def run
    parse_option(ARGV)
    @conf_path ||= File.join(ENV["HOME"], ".reposh.yaml")
    @system_name ||= guess_system

    @conf = load_config(@conf_path)
    @editing_mode = @conf["global"]["editing_mode"]
    pathext       = @conf["global"]["pathext"]
    @prompt      = get_conf(@system_name, "prompt")
    binpath      = get_conf(@system_name, "binpath") || @system_name
    default_cmd  = get_conf(@system_name, "default_cmd")

    @commands = Commands.new(binpath, default_cmd, pathext)
    @commands.register_custom_commands(@conf["global"]["custom_commands"])

    run_loop
  end

  def parse_option(args)
    o = OptionParser.new{|opt|
      opt.on("-c confpath",
             "path to .reposh.yaml"){|path|
        @confpath = path
      }
      opt.on("-s system",
             "vcs command name (eg. svn, svk, hg)"){|sys|
        @system_name = sys
      }
      opt.on("-h", "--help",
             "show this message"){
        puts opt
        exit
      }
      opt.on("-v", "--version",
             "show version information"){
        puts VERSION
        exit
      }
    }
    o.parse(args)
  end

  def load_config(path)
    if File.exist?(path)
      config_hash = YAML.load(File.read(path))
      puts "loaded config file: #{path}"
      CONF_DEFAULT.recursive_merge(config_hash)
    else
      CONF_DEFAULT
    end
  end

  def guess_system
    base = Pathname(Dir.pwd)
    loop do
      case 
      when (base + ".git").directory?
        return "git"
      when (base + ".hg").directory?
        return "hg"
      when (base + "_darcs").directory?
        return "darcs"
      when (base + ".svn").directory?
        return "svn"
      end

      if base.root?
        return  "svk"
      else
        base = base.parent
      end
    end
  end
  
  def get_conf(system, prop)
    (@conf["system"][system] and @conf["system"][system][prop]) or @conf["system"]["default"][prop] 
  end

  def run_loop
    if @editing_mode == "vi"
      Readline.vi_editing_mode
    end

    puts "Welcome to reposh #{VERSION} (mode: #{@system_name})"
    loop do
      cmd = Readline.readline(@prompt, true)
      @commands.dispatch(cmd, @system_name)
    end
  end

  class Commands
    def initialize(binpath, default_cmd, pathext)
      @binpath, @default_cmd, @pathext = binpath, default_cmd, pathext
      @commands = []
      register_builtin_commands
    end

    def register_builtin_commands
      # default command
      register(/.*/){|match|
        cmd = (match[0] == "") ? @default_cmd : match[0]
        execute "#{@binpath} #{cmd}"
      }

      # system commands
      register("%reload"){ 
        load __FILE__ 
      }
      register("%env"){
        require 'pp'
        pp ENV
      }
      register("%version"){
        puts VERSION 
      }
      register(/\A%ruby (.*)/){|match|
        puts "reposh: result is " + eval(match[1]).inspect
      }
      @trace_mode = false
      register("%trace"){
        @trace_mode = (not @trace_mode)
        puts "set trace_mode to #{@trace_mode}"
      }

      # exit commands
      exit_task = lambda{
        puts ""
        exit
      }
      register(nil,    &exit_task)
      register("exit", &exit_task)
      register("quit", &exit_task)

      # shell execution command
      register(/^:(.*)/){|match|
        execute match[1]
      }
    end

    def register_custom_commands(commands)
      commands.each do |hash|
        if hash["for"] 
          systems = hash["for"].split(/,/).map{|s| s.strip}
        else
          systems = nil
        end
        register(Regexp.new(hash["pattern"]), systems){|match|
          cmd = hash["rule"].
                  gsub(/\{system\}/, @binpath).
                  gsub(/\{\$(\d+)\}/){ match[$1.to_i] }
          puts cmd
          execute cmd
        }
      end
    end

    def register(pattern, systems = nil, &task)
      @commands.unshift [pattern, systems, task]
    end

    def dispatch(cmd, sys)
      @commands.each do |pattern, systems, task|
        next if systems && !systems.include?(sys)

        if (match = match?(pattern, cmd))
          return task.call(match)
        end
      end
      raise "must not happen"
    end

    def match?(pat, value)
      case pat
      when Regexp
        pat.match(value)
      when nil
        value == nil
      else
        pat.strip == value
      end
    end

    #require 'shell'
    def execute(cmd)
      stat = false
      ([""] + @pathext).each do |ext|
        command = add_ext(cmd, ext)
        puts command if @trace_mode
        #result = Shell.new.system(command) > $stdout
        result = system(command)
        return if result
        stat = $?
      end
      puts "reposh: failed to exec '#{cmd}': status #{stat.exitstatus}"
    end

    def add_ext(cmd, ext)
      exe, *args = cmd.split(' ')
      "#{exe}#{ext} #{args.join ' '}"
    end

  end

end

