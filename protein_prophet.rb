#
# This file is part of protk
# Created by Ira Cooke 17/1/2011
#
# Runs the Protein Prophet tool on a set of pep.xml files. The input can be generated by peptide_prophet or interprophet.
#
#

#!/bin/sh
# -------+---------+---------+-------- + --------+---------+---------+---------+
#     /  This section is a safe way to find the interpretter for ruby,  \
#    |   without caring about the user's setting of PATH.  This reduces  |
#    |   the problems from ruby being installed in different places on   |
#    |   various operating systems.  A much better solution would be to  |
#    |   use  `/usr/bin/env -S-P' , but right now `-S-P' is available    |
#     \  only on FreeBSD 5, 6 & 7.                        Garance/2005  /
# To specify a ruby interpreter set PROTK_RUBY_PATH in your environment. 
# Otherwise standard paths will be searched for ruby
#
if [ -z "$PROTK_RUBY_PATH" ] ; then
  
  for fname in /usr/local/bin /opt/csw/bin /opt/local/bin /usr/bin ; do
    if [ -x "$fname/ruby" ] ; then PROTK_RUBY_PATH="$fname/ruby" ; break; fi
  done
  
  if [ -z "$PROTK_RUBY_PATH" ] ; then
    echo "Unable to find a 'ruby' interpretter!"   >&2
    exit 1
  fi
fi

eval 'exec "$PROTK_RUBY_PATH" $PROTK_RUBY_FLAGS -rubygems -x -S $0 ${1+"$@"}'
echo "The 'exec \"$PROTK_RUBY_PATH\" -x -S ...' failed!" >&2
exit 1
#! ruby
#

$LOAD_PATH.unshift("#{File.dirname(__FILE__)}/lib/")

require 'constants'
require 'command_runner'
require 'prophet_tool'

# Setup specific command-line options for this tool. Other options are inherited from ProphetTool
#
prophet_tool=ProphetTool.new({:glyco=>true,:explicit_output=>true})
prophet_tool.option_parser.banner = "Run ProteinProphet on a set of pep.xml input files.\n\nUsage: protein_prophet.rb [options] file1.pep.xml file2.pep.xml ..."
prophet_tool.options.output_suffix="_protproph"
prophet_tool.option_parser.parse!

#/usr/local/tpp-4-4-0/bin/ProteinProphet /var/www/ISB/data/Data/microTOF/1011/MT219/combined_interact_iproph.pep.xml /var/www/ISB/data/Data/microTOF/1011/MT219/interact.prot.xml  GLYC

# Obtain a global environment object
genv=Constants.new

if ( prophet_tool.explicit_output==nil )
	output_file="#{prophet_tool.output_prefix}interact#{prophet_tool.output_suffix}.prot.xml"
 else 
	output_file=prophet_tool.explicit_output 
end

p output_file

if ( !Pathname.new(output_file).exist? || prophet_tool.over_write )

  cmd="#{genv.tpp_bin}/ProteinProphet "

  inputs = ARGV.collect {|file_name| 
    file_name.chomp
  }

  cmd << " #{inputs.join(" ")} #{output_file}"

  if ( prophet_tool.glyco )
    cmd << " GLYC "
  end

  # Run the analysis
  #
  jobscript_path="#{output_file}.pbs.sh"
  job_params={:jobid=>"protproph", :vmem=>"900mb", :queue => "lowmem"}
  genv.log("Running #{cmd}",:info)
  code = prophet_tool.run(cmd,genv,job_params,jobscript_path)
  throw "Command failed with exit code #{code}" unless code==0
else
  genv.log("Protein Prophet output file #{output_file} already exists. Run with -r option to replace",:warn)   
end






