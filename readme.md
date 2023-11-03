## Preamble
This script was written to process a pair of json input files containing a list of companies and a list of users and provide an output report.

The companies file format is a json array of objects with the following fields
```
id
name
top_up
email_status
```

The users file format is a json array of objects with the following fields
```
id
first_name
last_name
email
company_id
email_status
active_status
tokens
```

## Preconditions
This script targets ruby 3.2.2 and only uses the standard library.  It will ony run under ruby 3.2.2.

## Usage

The script will show its command line arguments by invoking help

```ruby exercise.rb --help```

To run the script on the command line simply invoke it using the ruby interpreter and pass in the two input file options.

```ruby exercise.rb --companies <company json file> --users <user json file>```

and it will provide an output file of output.txt

The script is designed to halt on most errors under the presumption that it is better to ensure an error is detected than to silently complete with incorrect output.
