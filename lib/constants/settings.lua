local Settings = {
  BOOKS = "books",
  LINK_BY_ISBN = "link_by_isbn",
  LINK_BY_HARDCOVER = "link_by_hardcover",
  LINK_BY_TITLE = "link_by_title",
  ALWAYS_SYNC = "always_sync",
  COMPATIBILITY_MODE = "compatibility_mode",
  USER_ID = "user_id",
  TRACK_FREQUENCY = "track_frequency",
  TRACK_METHOD = "track_method",
  TRACK_PERCENTAGE = "track_percentage",
  TRACK = {
    FREQUENCY = "frequency",
    PROGRESS = "progress",
  },
  SYNC = "sync",
}

Settings.AUTOLINK_OPTIONS = { Settings.LINK_BY_HARDCOVER, Settings.LINK_BY_ISBN, Settings.LINK_BY_TITLE }

return Settings
