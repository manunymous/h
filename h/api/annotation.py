from annotator import authz, document, es

from flask import current_app, g

TYPE = 'annotation'
MAPPING = {
    'annotator_schema_version': {'type': 'string'},
    'created': {'type': 'date'},
    'updated': {'type': 'date'},
    'quote': {'type': 'string'},
    'tags': {'type': 'string', 'index_name': 'not_analyzed'},
    'text': {'type': 'string'},
    'deleted': {'type': 'boolean'},
    'uri': {'type': 'string', 'index': 'not_analyzed'},
    'user': {'type': 'string', 'index': 'not_analyzed'},
    'consumer': {'type': 'string', 'index': 'not_analyzed'},

    'target': {
        'properties': {
            'id': {
                'type': 'multi_field',
                'path': 'just_name',
                'fields': {
                    'id': {'type': 'string', 'index': 'not_analyzed'},
                    'uri': {'type': 'string', 'index': 'not_analyzed'},
                },
            },
            'source': {
                'type': 'multi_field',
                'path': 'just_name',
                'fields': {
                    'source': {'type': 'string', 'index': 'not_analyzed'},
                    'uri': {'type': 'string', 'index': 'not_analyzed'},
                },
            },
            'selector': {
                'properties': {
                    'type': {'type': 'string', 'index': 'no'},

                    # Annotator XPath+offset selector
                    'startContainer': {'type': 'string', 'index': 'no'},
                    'startOffset': {'type': 'long', 'index': 'no'},
                    'endContainer': {'type': 'string', 'index': 'no'},
                    'endOffset': {'type': 'long', 'index': 'no'},

                    # Open Annotation TextQuoteSelector
                    'exact': {
                        'type': 'multi_field',
                        'path': 'just_name',
                        'fields': {
                            'exact': {'type': 'string'},
                            'quote': {'type': 'string'},
                        },
                    },
                    'prefix': {'type': 'string'},
                    'suffix': {'type': 'string'},

                    # Open Annotation (Data|Text)PositionSelector
                    'start': {'type': 'long'},
                    'end':   {'type': 'long'},
                }
            }
        }
    },

    'permissions': {
        'index_name': 'permission',
        'properties': {
            'read': {'type': 'string', 'index': 'not_analyzed'},
            'update': {'type': 'string', 'index': 'not_analyzed'},
            'delete': {'type': 'string', 'index': 'not_analyzed'},
            'admin': {'type': 'string', 'index': 'not_analyzed'}
        }
    },
    'references': {'type': 'string', 'index': 'not_analyzed'},
    'document': {
        'properties': document.MAPPING
    }
}


class Annotation(es.Model):

    __type__ = TYPE
    __mapping__ = MAPPING

    @classmethod
    def update_settings(cls):
        try:
            mapping = {cls.__type__: {'properties': cls.__mapping__}}
            cls.es.conn.indices.put_mapping(
                index=cls.es.index,
                doc_type=cls.__type__,
                body=mapping)
        finally:
            pass

    def save(self, *args, **kwargs):
        _add_default_permissions(self)

        # If the annotation includes document metadata look to see if we have
        # the document modeled already. If we don't we'll create a new one
        # If we do then we'll merge the supplied links into it.

        if 'document' in self:
            d = self['document']
            uris = [link['href'] for link in d['link']]
            docs = document.Document.get_all_by_uris(uris)

            if len(docs) == 0:
                doc = document.Document(d)
                doc.save()
            else:
                doc = docs[0]
                links = d.get('link', [])
                doc.merge_links(links)
                doc.save()

        super(Annotation, self).save(*args, **kwargs)

    @classmethod
    def _build_query(cls, offset=0, limit=20, **kwargs):
        q = super(Annotation, cls)._build_query(offset, limit, **kwargs)

        # attempt to expand query to include uris for other representations
        # using information we may have on hand about the Document
        if 'uri' in kwargs:
            term_filter = q['query']['filtered']['filter']
            doc = document.Document.get_by_uri(kwargs['uri'])
            if doc:
                new_terms = []
                for term in term_filter['and']:
                    if 'uri' in term['term']:
                        term = {'or': []}
                        for uri in doc.uris():
                            term['or'].append({'term': {'uri': uri}})
                    new_terms.append(term)

                term_filter['and'] = new_terms

        if current_app.config.get('AUTHZ_ON'):
            f = authz.permissions_filter(g.user)
            if not f:
                return False  # Refuse to perform the query
            q['query'] = {'filtered': {'query': q['query'], 'filter': f}}

        return q

    @classmethod
    def _build_query_raw(cls, request):
        q, p = super(Annotation, cls)._build_query_raw(request)

        if current_app.config.get('AUTHZ_ON'):
            f = authz.permissions_filter(g.user)
            if not f:
                return {'error': 'Authorization error!', 'status': 400}, None
            q['query'] = {'filtered': {'query': q['query'], 'filter': f}}

        return q, p


def _add_default_permissions(ann):
    if 'permissions' not in ann:
        ann['permissions'] = {'read': [authz.GROUP_CONSUMER]}