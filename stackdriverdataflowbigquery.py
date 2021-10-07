# Ref:
#   https://github.com/GoogleCloudPlatform/dialogflow-log-parser-dataflow-bigquery

import argparse
import json

import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions
from apache_beam.options.pipeline_options import StandardOptions

bigquery_table_schema = {
    "fields": [
        { "mode": "NULLABLE",
          "name": "insertId",
          "type": "STRING"
        },
        { "mode": "NULLABLE",
          "name": "timestamp",
          "type": "TIMESTAMP"
        },
        { "mode": "NULLABLE",
          "name": "player",
          "type": "STRING"
        },
        { "mode": "NULLABLE",
          "name": "action",
          "type": "STRING"
        },
        { "mode": "NULLABLE",
          "name": "textPayload",
          "type": "STRING"
        }
    ]
}

def myfilter(d):
    try:
        return d['logName'].endswith('/logs/stdout') \
                and 'connected\u001b[m' in d['textPayload'] \
                and not d['textPayload'].startswith('[BOT]')
    except:
        pass
    return False

def mytransform(d):
    retval = {
        'insertId'      : None,
        'timestamp'     : None,
        'player'        : None, # cl_name
        'action'        : None, # connected/ disconnected
        'textPayload'   : None,
    }

    try:
        retval['insertId'] = d['insertId']
        retval['timestamp'] = d['timestamp']
        retval['textPayload'] = d['textPayload']

        player, text = d['textPayload'].split('\u001b', 1)
        retval['player'] = player
        retval['action'] = 'disconnected' if 'disconnected' in text else 'connected'
    except:
        pass

    return retval
 
def run(argv=None, save_main_session=True):
    """Build and run the pipeline."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--input_topic', required=True,
        help=('Input PubSub topic of the form '
              '"projects/<PROJECT>/topics/<TOPIC>".'))
    parser.add_argument(
        '--output_bigquery', required=True,
        help=('Output BQ table to write results to '
              '"PROJECT_ID:DATASET.TABLE"'))
    known_args, pipeline_args = parser.parse_known_args(argv)

    pipeline_options = PipelineOptions(pipeline_args)
    pipeline_options.view_as(SetupOptions).save_main_session = save_main_session
    pipeline_options.view_as(StandardOptions).streaming = True
    p = beam.Pipeline(options=pipeline_options)
    
    ( p
      | 'From PubSub'     >> beam.io.ReadFromPubSub(topic=known_args.input_topic)
                                 .with_output_types(bytes)
      | 'To UTF-8'        >> beam.Map(lambda x: x.decode('utf-8'))
      | 'To Json'         >> beam.Map(json.loads)
      | 'MyFilter'        >> beam.Filter(myfilter)
      | 'MyTransform'     >> beam.Map(mytransform)
      | 'WriteToBigQuery' >> beam.io.WriteToBigQuery(
                                 known_args.output_bigquery,
                                 schema=bigquery_table_schema,
                                 create_disposition=beam.io.BigQueryDisposition.CREATE_IF_NEEDED,
                                 write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND
                             )
    )

    p.run()

if __name__ == '__main__':
    run()
