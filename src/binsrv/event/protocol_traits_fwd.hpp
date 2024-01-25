#ifndef BINSRV_EVENT_PROTOCOL_TRAITS_FWD_HPP
#define BINSRV_EVENT_PROTOCOL_TRAITS_FWD_HPP

#include <cstddef>
#include <cstdint>
#include <limits>
#include <string_view>

namespace binsrv::event {

inline constexpr std::uint16_t default_binlog_version{4U};
inline constexpr std::size_t default_number_of_events{42U};
inline constexpr std::size_t default_common_header_length{19U};

inline constexpr std::size_t unspecified_post_header_length{
    std::numeric_limits<std::size_t>::max()};

// https://github.com/mysql/mysql-server/blob/trunk/sql/log_event.h#L211
// 4 bytes which all binlogs should begin with
inline constexpr std::string_view magic_binlog_payload{"\xFE\x62\x69\x6E"};
inline constexpr std::uint64_t magic_binlog_offset{4ULL};

} // namespace binsrv::event

#endif // BINSRV_EVENT_PROTOCOL_TRAITS_FWD_HPP
