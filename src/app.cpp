#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>

#include "binsrv/basic_logger.hpp"
#include "binsrv/event_header.hpp"
#include "binsrv/exception_handling_helpers.hpp"
#include "binsrv/log_severity.hpp"
#include "binsrv/logger_factory.hpp"
#include "binsrv/master_config.hpp"

#include "easymysql/binlog.hpp"
#include "easymysql/connection.hpp"
#include "easymysql/connection_config.hpp"
#include "easymysql/library.hpp"

#include "util/command_line_helpers.hpp"
#include "util/exception_location_helpers.hpp"
#include "util/nv_tuple.hpp"

void log_span_dump(binsrv::basic_logger &logger,
                   easymysql::binlog_stream_span portion) {
  static constexpr std::size_t bytes_per_dump_line = 16;
  std::size_t offset = 0;
  while (offset < std::size(portion)) {
    std::ostringstream oss;
    oss << '[';
    oss << std::setfill('0') << std::hex;
    auto sub = portion.subspan(
        offset, std::min(bytes_per_dump_line, std::size(portion) - offset));
    for (const std::uint8_t current_byte : sub) {
      oss << ' ' << std::setw(2) << static_cast<std::uint16_t>(current_byte);
    }
    oss << " ]";
    logger.log(binsrv::log_severity::trace, oss.str());
    offset += bytes_per_dump_line;
  }
}

void log_generic_event(binsrv::basic_logger &logger,
                       const binsrv::event_header &generic_event) {
  std::ostringstream oss;
  oss << "ts: " << generic_event.get_readable_timestamp()
      << ", type:" << generic_event.get_readable_type_code()
      << ", server_id:" << generic_event.get_server_id()
      << ", event size:" << generic_event.get_event_size()
      << ", next event position:" << generic_event.get_next_event_position()
      << ", flags: (" << generic_event.get_readable_flags() << ')';

  logger.log(binsrv::log_severity::debug, oss.str());
}

int main(int argc, char *argv[]) {
  using namespace std::string_literals;

  int exit_code = EXIT_FAILURE;

  const auto cmd_args = util::to_command_line_agg_view(argc, argv);
  const auto number_of_cmd_args = std::size(cmd_args);
  const auto executable_name = util::extract_executable_name(cmd_args);

  if (number_of_cmd_args != binsrv::master_config::flattened_size + 1 &&
      number_of_cmd_args != 2) {
    std::cerr << "usage: " << executable_name
              << " <host> <port> <user> <password>\n"
              << "       " << executable_name << " <json_config_file>\n";
    return exit_code;
  }
  binsrv::basic_logger_ptr logger;

  try {
    const auto default_log_level = binsrv::log_severity::trace;

    const binsrv::logger_config initial_logger_config{
        {{default_log_level}, {""}}};

    logger = binsrv::logger_factory::create(initial_logger_config);
    // logging with "delimiter" level has the highest priority and empty label
    logger->log(binsrv::log_severity::delimiter,
                '"' + executable_name + '"' +
                    " started with the following command line arguments:");
    logger->log(binsrv::log_severity::delimiter,
                util::get_readable_command_line_arguments(cmd_args));

    binsrv::master_config_ptr config;
    if (number_of_cmd_args == 2) {
      logger->log(binsrv::log_severity::delimiter,
                  "Reading connection configuration from the JSON file.");
      config = std::make_shared<binsrv::master_config>(cmd_args[1]);
    } else if (number_of_cmd_args ==
               binsrv::master_config::flattened_size + 1) {
      logger->log(binsrv::log_severity::delimiter,
                  "Reading connection configuration from the command line "
                  "arguments.");
      config = std::make_shared<binsrv::master_config>(cmd_args.subspan(1U));
    } else {
      assert(false);
    }
    assert(config);

    const auto &logger_config = config->root().get<"logger">();
    if (!logger_config.has_file()) {
      logger->set_min_level(logger_config.get<"level">());
    } else {
      logger->log(binsrv::log_severity::delimiter,
                  "Redirecting logging to \"" + logger_config.get<"file">() +
                      "\"");
      auto new_logger = binsrv::logger_factory::create(logger_config);
      std::swap(logger, new_logger);
    }

    const auto log_level_label =
        binsrv::to_string_view(logger->get_min_level());
    logger->log(binsrv::log_severity::delimiter,
                "logging level set to \""s + std::string{log_level_label} +
                    '"');

    const auto &connection_config = config->root().get<"connection">();
    logger->log(binsrv::log_severity::info,
                "mysql connection string: " +
                    connection_config.get_connection_string());

    const easymysql::library mysql_lib;
    logger->log(binsrv::log_severity::info, "initialized mysql client library");

    std::string msg = "mysql client version: ";
    msg += mysql_lib.get_readable_client_version();
    logger->log(binsrv::log_severity::info, msg);

    auto connection = mysql_lib.create_connection(connection_config);
    logger->log(binsrv::log_severity::info,
                "established connection to mysql server");
    msg = "mysql server version: ";
    msg += connection.get_readable_server_version();
    logger->log(binsrv::log_severity::info, msg);

    logger->log(binsrv::log_severity::info,
                "mysql protocol version: " +
                    std::to_string(connection.get_protocol_version()));

    msg = "mysql server connection info: ";
    msg += connection.get_server_connection_info();
    logger->log(binsrv::log_severity::info, msg);

    msg = "mysql connection character set: ";
    msg += connection.get_character_set_name();
    logger->log(binsrv::log_severity::info, msg);

    static constexpr std::uint32_t default_server_id = 0;
    auto binlog = connection.create_binlog(default_server_id);
    logger->log(binsrv::log_severity::info, "opened binary log connection");

    easymysql::binlog_stream_span portion;
    while (!(portion = binlog.fetch()).empty()) {
      // Network streams are requested with COM_BINLOG_DUMP and
      // prepend each Binlog Event with 00 OK-byte.
      static constexpr unsigned char expected_event_prefix = '\0';
      if (portion[0] != expected_event_prefix) {
        util::exception_location().raise<std::invalid_argument>(
            "unexpected event prefix");
      }
      portion = portion.subspan(1U);
      logger->log(binsrv::log_severity::info,
                  "fetched " + std::to_string(std::size(portion)) +
                      "-byte(s) event from binlog");

      const binsrv::event_header generic_event{portion};
      log_generic_event(*logger, generic_event);
      log_span_dump(*logger, portion);
    }

    exit_code = EXIT_SUCCESS;
  } catch (...) {
    handle_std_exception(logger);
  }

  return exit_code;
}
