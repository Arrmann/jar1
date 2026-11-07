"""Small strict schemas for providers that support structured JSON output."""
def response_format(actions, *, verifier=False):
    string = {'type':'string'}
    number = {'type':'number'}
    boolean = {'type':'boolean'}
    def obj(properties):
        return {'type':'object','properties':properties,'required':list(properties),'additionalProperties':False}
    if verifier:
        schema = obj({'verified':boolean,'reason':string})
    else:
        field = obj({'id':string,'text':string,'clear':boolean})
        shapes = [obj(p) for p in [
            {}, {'id':string}, {'id':string,'button':{'type':'string','enum':['left','right']},'count':{'type':'integer','enum':[1,2]}},
            {'id':string,'text':string,'clear':boolean}, {'reason':string}, {'x':number,'y':number},
            {'keys':string}, {'direction':{'type':'string','enum':['up','down','left','right']},'count':{'type':'integer'}},
            {'name':string}, {'query':string}, {'url':string}, {'question':string}, {'seconds':number},
            {'answer':string,'evidence':string}, {'command':string},
            {'mode':{'type':'string','enum':['read','list','exists','write','copy','move','delete']},'path':string,
             'destination':{'type':['string','null']},'content':{'type':['string','null']}},
            {'name':{'type':'string','enum':['fill_fields']},'fields':{'type':'array','items':field}},
            {'name':{'type':'string','enum':['search']},'id':string,'text':string},
            {'query':string,'offset':{'type':'integer'}},
            {'query':string,'offset':{'type':'integer'},'scope':{'type':'string','enum':['elements','text']}},
        ]]
        # No nested sequences or control-flow tools. Host checks action/argument
        # compatibility and observes every step before dispatch.
        step_shapes = [shape for shape in shapes if not any(k in shape['properties'] for k in
            ('question','reason','x','answer','command','mode','seconds','query'))]
        step = obj({'action':{'type':'string','enum':['click','type','shortcut','scroll','switch','launch','browser_open','open_url','desktop','skill']},
                    'args':{'anyOf':step_shapes},'purpose':string,
                    'risk':{'type':'string','enum':['none','delete','send','overwrite','system']}})
        shapes.append(obj({'steps':{'type':'array','items':step,'minItems':2,'maxItems':6}}))
        schema = obj({'action':{'type':'string','enum':sorted(actions)},'args':{'anyOf':shapes},
            'purpose':string,'confidence':number,'risk':{'type':'string','enum':['none','delete','send','overwrite','system']},
            'clarification':string})
    return {'type':'json_schema','json_schema':{'name':'jarvis_verification' if verifier else 'jarvis_action',
        'strict':True,'schema':schema}}
