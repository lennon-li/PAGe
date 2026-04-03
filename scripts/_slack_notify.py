import urllib.request, json
token = 'xoxb-10658586573239-10682302249348-bRKbGaz6pWJAXJvGHlSFioAa'
msg = (
    ':white_check_mark: *loso_walkforward.qmd rendered successfully*\n\n'
    '*Changes made:*\n'
    '- Added `exclude_seasons` arg to `loso_walkforward()` -- 2015-16 excluded from all folds\n'
    '- New prospective peak MAE metric: weighted by exp(-0.1*(eval_week - iWeek_true)), post-peak weeks excluded, predicted peak rounded to integer\n'
    '- `tune_loso_k()` implemented and run over k_ref in {6, 8, 10, 12, 15, 20}\n\n'
    '*k_ref tuning results (prospective peak MAE, lower = better):*\n'
    '```\n'
    'k_ref   prosp_peak_mae\n'
    '    6         2.742\n'
    '    8         1.979  <-- best\n'
    '   10         2.163\n'
    '   12         2.176\n'
    '   15         2.274\n'
    '   20         2.329\n'
    '```\n'
    '*Recommendation: use k_ref = 8*\n\n'
    'Shutting down laptop now. Results in docs/loso_walkforward.html and data/k_ref_tuning.rds.'
)
payload = json.dumps({'channel': 'claude', 'text': msg}).encode()
req = urllib.request.Request(
    'https://slack.com/api/chat.postMessage',
    data=payload,
    headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}
)
resp = json.loads(urllib.request.urlopen(req).read())
print(resp.get('ok'), resp.get('error', ''))
