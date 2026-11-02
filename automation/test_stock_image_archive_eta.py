import json
import unittest
from datetime import datetime, timezone
from stock_image_archive_eta import estimate_from_lines

def iso(seconds):
    return datetime.fromtimestamp(seconds, timezone.utc).isoformat()

def sample(seconds, count):
    return iso(seconds) + ' ' + json.dumps({'total': 1000, 'processed': count})

class EstimateTests(unittest.TestCase):
    def estimate(self, lines, now, count=100, **job):
        return estimate_from_lines(lines, {'total':1000, 'processed':count},
                                   {'status':'running', 'heartbeat_at':iso(now), **job}, now)

    def test_recent_throughput_not_total_wall_time(self):
        result = self.estimate([sample(1000,80), sample(1060,90), sample(1120,100)],1120)
        self.assertEqual(result['minutes'],90)
        self.assertEqual(result['products_per_minute'],10)

    def test_long_stop_discards_old_session(self):
        result = self.estimate([sample(1000,10),sample(1060,20),sample(80000,80),
                                sample(80060,90),sample(80120,100)],80120)
        self.assertEqual(result['minutes'],90)
        self.assertEqual(result['sample_products'],20)

    def test_sleep_inside_window_discards_pre_sleep_samples(self):
        result = self.estimate([sample(1000,10),sample(1060,20),sample(1400,80),
                                sample(1460,90),sample(1520,100)],1520)
        self.assertEqual(result['minutes'],90)

    def test_stale_paused_and_backoff_do_not_claim_finish_time(self):
        lines = [sample(1000,80),sample(1060,90),sample(1120,100)]
        for state, job in [('inactive',{'heartbeat_at':iso(1000)}),
                           ('paused',{'status':'paused'}),
                           ('waiting',{'next_run_at':iso(1600)})]:
            result=self.estimate(lines,1400,**job)
            self.assertEqual(result['state'],state)
            self.assertIsNone(result['minutes'])

    def test_new_session_needs_enough_samples(self):
        self.assertEqual(self.estimate([sample(1000,80),sample(2000,100)],2000)['state'],
                         'measuring')

    def test_complete(self):
        self.assertEqual(self.estimate([],2000,status='complete')['minutes'],0)

if __name__ == '__main__':
    unittest.main()
