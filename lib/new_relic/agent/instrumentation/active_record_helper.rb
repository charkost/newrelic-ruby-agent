# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores/metric_helper'
require 'new_relic/agent/deprecator'

module NewRelic
  module Agent
    module Instrumentation
      module ActiveRecordHelper
        module_function

        # Used by both the AR 3.x and 4.x instrumentation
        def instrument_additional_methods
          instrument_save_methods
          instrument_relation_methods
        end

        def instrument_save_methods
          ::ActiveRecord::Base.class_eval do
            alias_method :save_without_newrelic, :save

            def save(*args, &blk)
              ::NewRelic::Agent.with_database_metric_name(self.class.name, nil, ACTIVE_RECORD) do
                save_without_newrelic(*args, &blk)
              end
            end

            alias_method :save_without_newrelic!, :save!

            def save!(*args, &blk)
              ::NewRelic::Agent.with_database_metric_name(self.class.name, nil, ACTIVE_RECORD) do
                save_without_newrelic!(*args, &blk)
              end
            end
          end
        end

        def instrument_relation_methods
          ::ActiveRecord::Relation.class_eval do
            alias_method :update_all_without_newrelic, :update_all

            def update_all(*args, &blk)
              ::NewRelic::Agent.with_database_metric_name(self.name, nil, ACTIVE_RECORD) do
                update_all_without_newrelic(*args, &blk)
              end
            end

            alias_method :delete_all_without_newrelic, :delete_all

            def delete_all(*args, &blk)
              ::NewRelic::Agent.with_database_metric_name(self.name, nil, ACTIVE_RECORD) do
                delete_all_without_newrelic(*args, &blk)
              end
            end

            alias_method :destroy_all_without_newrelic, :destroy_all

            def destroy_all(*args, &blk)
              ::NewRelic::Agent.with_database_metric_name(self.name, nil, ACTIVE_RECORD) do
                destroy_all_without_newrelic(*args, &blk)
              end
            end

            alias_method :calculate_without_newrelic, :calculate

            def calculate(*args, &blk)
              ::NewRelic::Agent.with_database_metric_name(self.name, nil, ACTIVE_RECORD) do
                calculate_without_newrelic(*args, &blk)
              end
            end

            if method_defined?(:pluck)
              alias_method :pluck_without_newrelic, :pluck

              def pluck(*args, &blk)
                ::NewRelic::Agent.with_database_metric_name(self.name, nil, ACTIVE_RECORD) do
                  pluck_without_newrelic(*args, &blk)
                end
              end
            end
          end
        end

        ACTIVE_RECORD = "ActiveRecord".freeze unless defined?(ACTIVE_RECORD)
        OTHER         = "other".freeze unless defined?(OTHER)

        def product_operation_collection_for name, sql, adapter_name
          product   = map_product(adapter_name)
          splits    = split_name(name)
          model     = model_from_splits(splits)
          operation = operation_from_splits(splits, sql)
          NewRelic::Agent::Datastores::MetricHelper.product_operation_collection_for product, operation, model, ACTIVE_RECORD
        end

        # @deprecated
        def rollup_metrics_for(*_)
          NewRelic::Agent::Deprecator.deprecate("ActiveRecordHelper.rollup_metrics_for",
                                                "NewRelic::Agent::Datastores::MetricHelper.metrics_for")

          rollup_metric = if NewRelic::Agent::Transaction.recording_web_transaction?
            NewRelic::Agent::Datastores::MetricHelper::WEB_ROLLUP_METRIC
          else
            NewRelic::Agent::Datastores::MetricHelper::OTHER_ROLLUP_METRIC
          end

          [rollup_metric,
           NewRelic::Agent::Datastores::MetricHelper::ROLLUP_METRIC]
        end

        SPACE = ' '.freeze unless defined?(SPACE)
        EMPTY = [].freeze unless defined?(EMPTY)

        def split_name(name)
          if name && name.respond_to?(:split)
            name.split(SPACE)
          else
            EMPTY
          end
        end

        def model_from_splits(splits)
          if splits.length == 2
            splits.first
          else
            nil
          end
        end

        def operation_from_splits(splits, sql)
          if splits.length == 2
            map_operation(splits[1])
          else
            NewRelic::Agent::Database.parse_operation_from_query(sql) || OTHER
          end
        end

        # These are used primarily to optimize and avoid allocation on well
        # known operations coming in. Anything not matching the list is fine,
        # it just needs to get downcased directly for use.
        OPERATION_NAMES = {
          'Find'    => 'find',
          'Load'    => 'find',
          'Count'   => 'find',
          'Exists'  => 'find',
          'Create'  => 'create',
          'Columns' => 'columns',
          'Indexes' => 'indexes',
          'Destroy' => 'destroy',
          'Update'  => 'update',
          'Save'    => 'save'
        }.freeze unless defined?(OPERATION_NAMES)

        def map_operation(raw_operation)
          direct_op = OPERATION_NAMES[raw_operation]
          return direct_op if direct_op

          raw_operation.downcase
        end

        PRODUCT_NAMES = {
          "mysql"      => "MySQL",
          "mysql2"     => "MySQL",

          "postgresql" => "Postgres",

          "sqlite3"    => "SQLite",

          # https://rubygems.org/gems/activerecord-jdbcpostgresql-adapter
          "jdbcmysql"  => "MySQL",

          # https://rubygems.org/gems/activerecord-jdbcpostgresql-adapter
          "jdbcpostgresql" => "Postgres",

          # https://rubygems.org/gems/activerecord-jdbcsqlite3-adapter
          "jdbcsqlite3"    => "SQLite",

          # https://rubygems.org/gems/activerecord-jdbcderby-adapter
          "derby"      => "Derby",
          "jdbcderby"  => "Derby",

          # https://rubygems.org/gems/activerecord-jdbc-adapter
          "jdbc"       => "JDBC",

          # https://rubygems.org/gems/activerecord-jdbcmssql-adapter
          "jdbcmssql"  => "MSSQL",
          "mssql"      => "MSSQL",

          # https://rubygems.org/gems/activerecord-sqlserver-adapter
          "sqlserver"  => "MSSQL",

          # https://rubygems.org/gems/activerecord-odbc-adapter
          "odbc"       => "ODBC",

          # https://rubygems.org/gems/activerecord-oracle_enhanced-adapter
          "oracle_enhanced" => "Oracle"
        }.freeze unless defined?(PRODUCT_NAMES)

        ACTIVE_RECORD_DEFAULT_PRODUCT_NAME = "ActiveRecord".freeze unless defined?(ACTIVE_RECORD_DEFAULT_PRODUCT_NAME)

        def map_product(adapter_name)
          PRODUCT_NAMES.fetch(adapter_name,
                              ACTIVE_RECORD_DEFAULT_PRODUCT_NAME)
        end

        module InstanceIdentifier
          extend self

          LOCALHOST = %w[
            localhost
            0.0.0.0
            127.0.0.1
            0:0:0:0:0:0:0:1
            0:0:0:0:0:0:0:0
            ::1
            ::
          ].freeze unless defined?(LOCALHOST)

          PRODUCT_SYMBOLS = {
            "mysql"      => :mysql,
            "mysql2"     => :mysql,
            "jdbcmysql"  => :mysql,

            "postgresql"     => :postgres,
            "jdbcpostgresql" => :postgres
          }.freeze unless defined?(PRODUCT_SYMBOLS)

          DATASTORE_DEFAULT_PORTS = {
            :mysql    => 3306,
            :postgres => 5432
          }.freeze unless defined?(DATASTORE_DEFAULT_PORTS)

          DEFAULT = "default".freeze unless defined?(DEFAULT)
          UNKNOWN_INSTANCE = "unknown:unknown".freeze unless defined?(UNKNOWN_INSTANCE)
          UNKNOWN = "unknown".freeze unless defined?(UNKNOWN)
          SLASH = "/".freeze unless defined?(SLASH)

          def for(config)
            return UNKNOWN_INSTANCE unless config

            symbolized_adapter = PRODUCT_SYMBOLS[config[:adapter]]
            host = determine_host(config[:host], symbolized_adapter)
            port_path_or_id = determine_ppi(config, symbolized_adapter)

            "#{host}/#{port_path_or_id}"
          end

          private

          def determine_host(configured_value, adapter)
            if configured_value.nil? ||
              LOCALHOST.include?(configured_value) ||
              postgres_unix_domain_socket_case?(configured_value, adapter)

              Hostname.get
            elsif configured_value.empty?
              UNKNOWN
            else
              configured_value
            end
          end

          def determine_ppi(config, adapter)
            if config[:socket]
              config[:socket].empty? ? UNKNOWN : config[:socket]
            elsif postgres_unix_domain_socket_case?(config[:host], adapter) || mysql_default_case?(config, adapter)
              DEFAULT
            elsif config[:port].nil?
              DATASTORE_DEFAULT_PORTS[adapter] || DEFAULT
            elsif config[:port].is_a?(Fixnum) || config[:port].to_i != 0
              config[:port]
            else
              UNKNOWN
            end
          end

          def postgres_unix_domain_socket_case?(host, adapter)
            adapter == :postgres && host && host.start_with?(SLASH)
          end

          def mysql_default_case?(config, adapter)
            (adapter == :mysql2 || adapter == :mysql) &&
              LOCALHOST.include?(config[:host]) &&
              !config[:port]
          end
        end
      end
    end
  end
end
