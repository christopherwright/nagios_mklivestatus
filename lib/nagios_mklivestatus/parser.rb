# This module can be used to parse a nagios string query 
# in order to convert it into a Nagios::MkLiveStatus::Query
#
# Author::    Esco-lan Team  (mailto:team@esco-lan.org)
# Copyright:: Copyright (c) 2012 GIP RECIA
# License::   General Public Licence
module Nagios::MkLiveStatus::Parser
  
  include Nagios::MkLiveStatus
  include Nagios::MkLiveStatus::QueryHelper
  
  #
  # Parser method, takes the string and, optionally, a boolean to add opts
  # And return a Nagios::MkLiveStatus::Query and query options (if asked)
  #
  def nagmk_parse(query_str, with_opts=false)
    
    if not query_str.is_a? String or query_str.empty?
      ex = QueryException.new("The query is not valid. You must provide a valid string.")
      logger.error(ex.message)
      raise ex
    end
    
    query = nagmk_query()
    nagios_opts = {}
    
    #split all the lines in order to create a table of string commands
    commands = query_str.split("\n")
    
    # the first line is the GET of the query
    get = commands.shift.strip.match(/^GET (.*)$/)
    if get == nil
      ex = QueryException.new("The query has no GET. The first line must match /^GET (.*)$/.")
      logger.error(ex.message)
      raise ex
    else
      query.get get[1]
    end
    
    columns_parsed=false
    query_parsed=false
    stats = []
    columns = []
    filters = []
    
    commands.each do |command|
      command.strip!
      logger.debug("> processing command \"#{command}\"")
      
      #if end query found, columns must be parsed
      if query_parsed and not columns_parsed
        columns_parsed = true
      end
      
      if command.match(/^Columns: /)
        
        if query_parsed
          ex = QueryException.new("The Query Options must be defined after Columns : #{command}")
          logger.error(ex.message)
          raise ex
        end
        
        if not columns_parsed
          logger.debug(">> columns found \"#{command.match(/^Columns: (.*)$/)[1]}\"")
          columns = command.match(/^Columns: (.*)$/)[1].split(" ")
          columns_parsed = true
        else
          ex = QueryException.new("The definitions of columns are encountered twice. Or after the Filter predicates.")
          logger.error(ex.message)
          raise ex
        end
      elsif command.match(/^Stats(And|Or)?: /)
        
        if columns_parsed
          ex = QueryException.new("The stats predicates must be defined before Columns : #{command}")
          logger.error(ex.message)
          raise ex
        end
        
        if query_parsed
          ex = QueryException.new("The Query Options must be defined after Stats : #{command}")
          logger.error(ex.message)
          raise ex
        end
        
        stats_dispatching(command, stats)
        
      elsif command.match(/^(Filter: |And: |Or: |Negate:)/)
        
        if not columns_parsed
          columns_parsed = true
        end
        
        if query_parsed
          ex = QueryException.new("The Query Options must be defined after Filters : #{command}")
          logger.error(ex.message)
          raise ex
        end
        
        filter_dispatching(command, filters)
        
      elsif command.match(/^UserAuth: (.+)$/)
        query_parsed = true
        nagios_opts[:user] = command.match(/^UserAuth: (.+)$/)[1]
        
      elsif command.match(/^ColumnHeaders: (on|off)$/)
        query_parsed = true
        nagios_opts[:column_headers] = command.match(/^ColumnHeaders: (on|off)$/)[1] == "on"
        
      elsif command.match(/^Limit: (\d+)$/)
        query_parsed = true
        nagios_opts[:limit] = command.match(/^Limit: (\d+)$/)[1].to_i
        
      elsif command.match(/^OutputFormat: (json|python)$/)
        query_parsed = true
        nagios_opts[:output] = command.match(/^OutputFormat: (json|python)$/)[1]
        
      elsif not command.empty?
        ex = QueryException.new("The current query is not valid due to : #{command}")
        logger.error(ex.message)
        raise ex
      end
      
    end
    
    columns.each do |column|
      query.addColumn column
    end
    
    filters.each do |filter|
      query.addFilter filter
    end
    
    stats.each do |stat|
      query.addStats stat
    end
    
    if with_opts
      return query, nagios_opts
    else
      return query
    end
  end
  
private
  def stats_dispatching(command, stats=[])
    if command.match(/^Stats: /)
      
      stats.push nagmk_stats_from_str(command)
      
    elsif command.match(/^StatsAnd: /)
      number = command.match(/^StatsAnd: (\d)$/)[1].to_i
      if number <= 1
        ex = QueryException.new("The StatAnd predicate must be above 1.")
        logger.error(ex.message)
        raise ex
      end
      
      (number-1).times do |idx|
        stats.push nagmk_stats_and(stats.pop, stats.pop)
      end
    elsif command.match(/^StatsOr: /)
      number = command.match(/^StatsOr: (\d)$/)[1].to_i
      if number <= 1
        ex = QueryException.new("The StatOr predicate must be above 1.")
        logger.error(ex.message)
        raise ex
      end
      
      (number-1).times do |idx|
        stats.push nagmk_stats_or(stats.pop, stats.pop)
      end
    end
  end
  
  def filter_dispatching(command, filters=[])
    if command.match(/^Filter: /)
      
      filters.push nagmk_filter_from_str(command)
      
    elsif command.match(/^And: /)
      number = command.match(/^And: (\d)$/)[1].to_i
      if number <= 1
        ex = QueryException.new("The And predicate must be above 1.")
        logger.error(ex.message)
        raise ex
      end
      
      (number-1).times do |idx|
        filters.push nagmk_and(filters.pop, filters.pop)
      end
    elsif command.match(/^Or: /)
      number = command.match(/^Or: (\d)$/)[1].to_i
      if number <= 1
        ex = QueryException.new("The Or predicate must be above 1.")
        logger.error(ex.message)
        raise ex
      end
      
      (number-1).times do |idx|
        filters.push nagmk_or(filters.pop, filters.pop)
      end
    elsif command.match(/^Negate:/)
      filters.push nagmk_negate(filters.pop)
    end
  end
end