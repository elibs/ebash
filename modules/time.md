# Module time


## func etimestamp

`etimestamp` is used to emit a timestamp in a standard format that we use through ebash. The format that we used is
controlled via `ETIMESTAMP_FORMAT` and defaults to `RFC3339`.

## func etimestamp_rfc3339

`etimestamp_rfc3339` is a more explicit version of `etimestamp` which emits the time format in `RFC3339` format regardless
of the value of `ETIMESTAMP_FORMAT`.
